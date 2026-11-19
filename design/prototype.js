"use strict";

const DAYS = [
  { id: "mon", short: "Mon", name: "Monday" },
  { id: "tue", short: "Tue", name: "Tuesday" },
  { id: "wed", short: "Wed", name: "Wednesday" },
  { id: "thu", short: "Thu", name: "Thursday" },
  { id: "fri", short: "Fri", name: "Friday" },
  { id: "sat", short: "Sat", name: "Saturday" },
  { id: "sun", short: "Sun", name: "Sunday" }
];
const WEEKEND = ["sat", "sun"];
const COLORS = [
  { id: "blue", name: "Blue" },
  { id: "teal", name: "Teal" },
  { id: "green", name: "Green" },
  { id: "purple", name: "Purple" },
  { id: "pink", name: "Pink" },
  { id: "red", name: "Red" },
  { id: "orange", name: "Orange" },
  { id: "gray", name: "Gray" }
];
const COURSE_COLOR = "blue";
const UNAVAILABLE_COLOR = "gray";
const HOUR = 56;
const RESULT_LIMIT = 500;

const appEl = document.getElementById("app");
const overlayEl = document.getElementById("overlay");
const phoneEl = document.getElementById("phone");
const statusEl = document.getElementById("status");

let seq = 0;
const uid = (prefix) => `${prefix}${++seq}`;
const clone = (value) => JSON.parse(JSON.stringify(value));
const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const countText = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;

const meeting = (label, days, start, end) => ({ id: uid("m"), label, days, start, end });
const section = (label, meetings) => ({ id: uid("s"), label, meetings });
const course = (code, name, sections) => ({ id: uid("c"), code, name, color: COURSE_COLOR, sections });
const block = (name, times) => ({ id: uid("u"), name, color: UNAVAILABLE_COLOR, times: times.map(([days, start, end]) => ({ id: uid("t"), days, start, end })) });

function seedStore(mode) {
  if (mode === "new") return { plans: [] };
  const chem = (sections) => course("CHEM 101", "Chemistry", sections);
  const chem01 = () => section("01", [meeting("Lecture", ["tue"], "15:00", "16:00"), meeting("Lab", ["thu"], "10:00", "11:00")]);
  const math = () => course("MATH 120", "Calculus", [section("01", [meeting("Lecture", ["mon", "wed"], "11:00", "12:00"), meeting("Tutorial", ["wed"], "12:00", "12:15")])]);
  const fixed = () => [block("Work", [[["tue"], "14:00", "17:00"]]), block("Weekend shift", [[["sat"], "10:00", "12:00"]])];
  return {
    plans: [
      {
        id: uid("p"),
        name: "Fall 2026",
        courses: [
          chem([
            chem01(),
            section("02", [meeting("Lecture", ["mon", "wed"], "09:00", "10:00"), meeting("Lab", ["wed"], "10:00", "10:30")]),
            section("03", [meeting("Lecture", ["tue", "thu"], "09:00", "10:00"), meeting("Lab", ["thu"], "10:00", "10:30")])
          ]),
          math()
        ],
        unavailable: fixed(),
        starred: []
      },
      { id: uid("p"), name: "Fall 2026 (2)", courses: [chem([chem01()]), math()], unavailable: fixed(), starred: [] },
      {
        id: uid("p"),
        name: "Spring 2026",
        courses: [
          course("ENGL 101", "Composition", [
            section("01", [meeting("Lecture", ["mon", "wed", "fri"], "08:00", "08:50")]),
            section("02", [meeting("Lecture", ["tue", "thu"], "13:00", "14:15")])
          ]),
          course("PHYS 211", "Physics I", [section("01", [meeting("Lecture", ["mon", "wed", "fri"], "10:00", "10:50"), meeting("Lab", ["tue"], "14:00", "16:00")])]),
          course("CHEM 203", "Organic Chemistry", [section("01", [meeting("Lecture", ["tue", "thu"], "11:00", "12:15")])])
        ],
        unavailable: [block("Work", [[["tue", "thu"], "16:00", "20:00"]])],
        starred: []
      }
    ]
  };
}

const app = {
  mode: "new",
  store: null,
  stack: [{ screen: "plans" }],
  sheet: null,
  sheetOpener: null,
  toast: null,
  toastTimer: null,
  suggestFor: null,
  suggestTyped: false,
  copyOffer: null,
  nameBefore: "",
  cursor: {},
  events: [],
  focus: null,
  scrollTo: null,
  view: { mode: "week", weekends: true, weekStart: "mon", sort: "days" },
  theme: "auto",
  largeText: false,
  landscape: false
};

const route = () => app.stack[app.stack.length - 1];
const findPlan = (id) => app.store.plans.find((p) => p.id === id);
const currentPlan = () => findPlan(route().planId);

function upcomingTerm(date = new Date()) {
  const month = date.getMonth();
  const year = date.getFullYear();
  if (month >= 9) return `Spring ${year + 1}`;
  if (month === 0) return `Spring ${year}`;
  return `Fall ${year}`;
}

function uniqueName(base) {
  const names = new Set(app.store.plans.map((p) => p.name.trim().toLowerCase()));
  if (!names.has(base.toLowerCase())) return base;
  let n = 2;
  while (names.has(`${base} (${n})`.toLowerCase())) n += 1;
  return `${base} (${n})`;
}

const toMin = (t) => {
  const [h, m] = t.split(":").map(Number);
  return h * 60 + m;
};

function clock(min, suffix = true) {
  const h = Math.floor(min / 60);
  const m = min % 60;
  return `${h % 12 || 12}${m ? `:${String(m).padStart(2, "0")}` : ""}${suffix ? (h < 12 ? " AM" : " PM") : ""}`;
}

function rangeMin(s, e) {
  return (s < 720) === (e < 720) ? `${clock(s, false)}–${clock(e)}` : `${clock(s)}–${clock(e)}`;
}

const range = (start, end) => rangeMin(toMin(start), toMin(end));
const hourLabel = (h) => `${h % 12 || 12} ${h < 12 || h === 24 ? "AM" : "PM"}`;
const dayInfo = (id) => DAYS.find((d) => d.id === id);

function dayOrder() {
  const ids = DAYS.map((d) => d.id);
  return app.view.weekStart === "sun" ? ["sun", ...ids.slice(0, 6)] : ids;
}

const daysText = (days) => dayOrder().filter((d) => days.includes(d)).map((d) => dayInfo(d).short).join(", ");

function durationText(min) {
  const h = Math.floor(min / 60);
  const m = min % 60;
  return [h && `${h} hr`, m && `${m} min`].filter(Boolean).join(" ");
}

const gapsText = (min) => (min ? `${durationText(min)} gaps` : "No gaps");

function overlapText(a, b) {
  const day = dayOrder().find((d) => a.days.includes(d) && b.days.includes(d));
  return `${dayInfo(day).short} ${rangeMin(Math.max(toMin(a.start), toMin(b.start)), Math.min(toMin(a.end), toMin(b.end)))}`;
}

const timeValid = (t) => t.days.length > 0 && Boolean(t.start) && Boolean(t.end) && toMin(t.end) > toMin(t.start);
const courseTitle = (c) => c.code.trim() || c.name.trim() || "New course";
const blockTitle = (u) => u.name.trim() || "Unavailable";
const courseComplete = (c) => Boolean(c.code.trim() || c.name.trim()) && c.sections.length > 0 && c.sections.every((s) => s.meetings.length > 0 && s.meetings.every(timeValid));
const blockComplete = (u) => u.times.length > 0 && u.times.every(timeValid);
const blankTime = (t) => !t.days.length && !t.start && !t.end;
const isEmptyCourse = (c) => !c.code.trim() && !c.name.trim() && c.sections.every((s) => s.meetings.every(blankTime));
const isEmptyBlock = (u) => !u.name.trim() && u.times.every(blankTime);

const overlaps = (a, b) => a.days.some((d) => b.days.includes(d)) && toMin(a.start) < toMin(b.end) && toMin(b.start) < toMin(a.end);
const blockTimes = (plan) => plan.unavailable.flatMap((u) => u.times.map((t) => ({ ...t, owner: u })));

function sectionBlockers(sec, times) {
  const hits = [];
  for (const m of sec.meetings) for (const t of times) if (overlaps(m, t)) hits.push({ meeting: m, time: t });
  return hits;
}

function sectionsClash(a, b) {
  for (const m of a.meetings) for (const n of b.meetings) if (overlaps(m, n)) return { a: m, b: n };
  return null;
}

function makeStats(sections) {
  const meetings = sections.flatMap((s) => s.meetings);
  const days = new Set(meetings.flatMap((m) => m.days));
  let gaps = 0;
  for (const d of days) {
    const list = meetings.filter((m) => m.days.includes(d)).map((m) => [toMin(m.start), toMin(m.end)]).sort((a, b) => a[0] - b[0]);
    let end = list[0][1];
    for (const [s, e] of list.slice(1)) {
      if (s > end) gaps += s - end;
      end = Math.max(end, e);
    }
  }
  return {
    days: days.size,
    gaps,
    first: Math.min(...meetings.map((m) => toMin(m.start))),
    last: Math.max(...meetings.map((m) => toMin(m.end)))
  };
}

function analyze(plan) {
  if (!plan.courses.length) return { status: "empty" };
  const incomplete = [
    ...plan.courses.filter((c) => !courseComplete(c)).map((c) => ({ title: courseTitle(c), screen: "course", key: "courseId", id: c.id })),
    ...plan.unavailable.filter((u) => !blockComplete(u)).map((u) => ({ title: blockTitle(u), screen: "block", key: "blockId", id: u.id }))
  ];
  if (incomplete.length) return { status: "incomplete", incomplete };
  const times = blockTimes(plan);
  const open = plan.courses.map((c) => ({ course: c, sections: c.sections.filter((s) => !sectionBlockers(s, times).length) }));
  const schedules = [];
  const picks = [];
  let truncated = false;
  const walk = (i) => {
    if (schedules.length >= RESULT_LIMIT) {
      truncated = true;
      return;
    }
    if (i === open.length) {
      schedules.push({ key: picks.map((p) => p.section.id).sort().join("|"), picks: picks.slice(), ...makeStats(picks.map((p) => p.section)) });
      return;
    }
    for (const s of open[i].sections) {
      if (picks.some((p) => sectionsClash(p.section, s))) continue;
      picks.push({ course: open[i].course, section: s });
      walk(i + 1);
      picks.pop();
    }
  };
  walk(0);
  if (schedules.length) return { status: "fits", schedules, truncated };
  return { status: "none", reasons: explain(open, times) };
}

function explain(open, times) {
  const blocked = open.filter((o) => !o.sections.length).map(({ course: c }) => ({
    kind: "blocked",
    course: c,
    hits: c.sections.map((s) => ({ section: s, hit: sectionBlockers(s, times)[0] }))
  }));
  if (blocked.length) return blocked;
  const pairs = [];
  for (let i = 0; i < open.length; i += 1) {
    for (let j = i + 1; j < open.length; j += 1) {
      const clashes = [];
      const always = open[i].sections.every((a) => open[j].sections.every((b) => {
        const hit = sectionsClash(a, b);
        if (hit) clashes.push({ a, b, hit });
        return Boolean(hit);
      }));
      if (always) pairs.push({ kind: "pair", first: open[i].course, second: open[j].course, clashes });
    }
  }
  return pairs.length ? pairs : [{ kind: "combo" }];
}

function sortSchedules(list) {
  const [a, b] = app.view.sort === "gaps" ? ["gaps", "days"] : ["days", "gaps"];
  return [...list].sort((x, y) => x[a] - y[a] || x[b] - y[b] || x.first - y.first || x.last - y.last || x.key.localeCompare(y.key));
}

function library(excludeCourseId) {
  const entries = new Map();
  for (const p of app.store.plans) {
    for (const c of p.courses) {
      const code = c.code.trim();
      if (c.id === excludeCourseId || !code || !courseComplete(c) || entries.has(code.toLowerCase())) continue;
      entries.set(code.toLowerCase(), { code, name: c.name.trim(), color: c.color, sections: c.sections, from: p.name });
    }
  }
  return [...entries.values()].sort((a, b) => a.code.localeCompare(b.code));
}

function classEvent(c, s, m, extra = {}) {
  return { key: m.id, kind: "class", ref: { type: "course", id: c.id }, title: courseTitle(c), name: c.name, color: c.color, sectionLabel: s.label, label: m.label, days: m.days, start: m.start, end: m.end, ...extra };
}

function blockEvent(u, t, extra = {}) {
  return { key: t.id, kind: "block", ref: { type: "block", id: u.id }, title: blockTitle(u), color: u.color, days: t.days, start: t.start, end: t.end, ...extra };
}

function scheduleEvents(plan, picks) {
  return [
    ...picks.flatMap(({ course: c, section: s }) => s.meetings.map((m) => classEvent(c, s, m))),
    ...plan.unavailable.flatMap((u) => u.times.map((t) => blockEvent(u, t)))
  ];
}

function conflictEvents(reasons) {
  const events = new Map();
  const bands = [];
  const band = (a, b) => {
    for (const day of a.days.filter((d) => b.days.includes(d))) {
      const s = Math.max(toMin(a.start), toMin(b.start));
      const e = Math.min(toMin(a.end), toMin(b.end));
      if (s < e) bands.push({ day, s, e });
    }
  };
  for (const r of reasons) {
    if (r.kind === "blocked") {
      for (const { section: s, hit } of r.hits) {
        events.set(hit.meeting.id, classEvent(r.course, s, hit.meeting, { conflict: true }));
        events.set(hit.time.id, blockEvent(hit.time.owner, hit.time, { conflict: true }));
        band(hit.meeting, hit.time);
      }
    } else if (r.kind === "pair") {
      for (const { a, b, hit } of r.clashes.slice(0, 4)) {
        events.set(hit.a.id, classEvent(r.first, a, hit.a, { conflict: true }));
        events.set(hit.b.id, classEvent(r.second, b, hit.b, { conflict: true }));
        band(hit.a, hit.b);
      }
    }
  }
  return { events: [...events.values()], bands };
}

function visibleDays(events) {
  const classWeekend = new Set(events.filter((e) => e.kind === "class").flatMap((e) => e.days));
  return dayOrder().filter((d) => app.view.weekends || !WEEKEND.includes(d) || classWeekend.has(d));
}

function layoutDay(items) {
  items.sort((a, b) => a.s - b.s || b.t - a.t);
  let cluster = [];
  let clusterEnd = -1;
  const flush = () => {
    const lanes = [];
    for (const item of cluster) {
      let lane = lanes.findIndex((end) => end <= item.s);
      if (lane < 0) {
        lane = lanes.length;
        lanes.push(0);
      }
      lanes[lane] = item.t;
      item.lane = lane;
    }
    for (const item of cluster) item.lanes = lanes.length;
    cluster = [];
  };
  for (const item of items) {
    if (cluster.length && item.s >= clusterEnd) {
      flush();
      clusterEnd = -1;
    }
    cluster.push(item);
    clusterEnd = Math.max(clusterEnd, item.t);
  }
  flush();
  return items;
}

function eventLabel(e, day) {
  const detail = e.kind === "class" ? [`Section ${e.sectionLabel}`, e.label].filter(Boolean).join(" ") : "unavailable";
  return `${e.title}, ${detail}, ${dayInfo(day).name} ${range(e.start, e.end)}${e.conflict ? ", conflict" : ""}`;
}

function calendarHtml(events, bands) {
  const days = bands.length ? dayOrder().filter((d) => bands.some((b) => b.day === d)) : visibleDays(events);
  const shown = events.filter((e) => e.days.some((d) => days.includes(d)));
  const startH = shown.length ? Math.floor(Math.min(...shown.map((e) => toMin(e.start))) / 60) : 8;
  const endH = shown.length ? Math.ceil(Math.max(...shown.map((e) => toMin(e.end))) / 60) : 17;
  const hours = Math.max(endH - startH, 1);
  const y = (min) => ((min - startH * 60) / 60) * HOUR;
  const labels = Array.from({ length: hours + 1 }, (_, i) => `<span style="top:${i * HOUR}px">${hourLabel(startH + i)}</span>`).join("");
  const columns = days.map((d) => {
    const items = layoutDay(shown.filter((e) => e.days.includes(d)).map((e) => ({ e, s: toMin(e.start), t: toMin(e.end) })));
    const blocks = items.map(({ e, s, t, lane, lanes }) => `<button class="ev ${e.kind === "block" ? "ev-block" : "ev-class"} tone-${e.color}${e.conflict ? " ev-conflict" : ""}" type="button" data-action="event" data-event="${e.key}" data-key="ev-${e.key}-${d}" style="top:${y(s)}px;height:${y(t) - y(s)}px;left:calc(${lane} * 100% / ${lanes});width:calc(100% / ${lanes})" aria-label="${esc(eventLabel(e, d))}"><span class="ev-title">${esc(e.title)}</span><span class="ev-time">${esc(rangeMin(s, t))}</span></button>`).join("");
    const marks = bands.filter((b) => b.day === d).map((b) => `<span class="band" style="top:${y(b.s)}px;height:${y(b.e) - y(b.s)}px" aria-hidden="true"></span>`).join("");
    return `<div class="cal-day" role="group" aria-label="${dayInfo(d).name}">${blocks}${marks}</div>`;
  }).join("");
  return `<div class="cal" style="--days:${days.length}"><div class="cal-head" aria-hidden="true"><span></span>${days.map((d) => `<span>${dayInfo(d).short}</span>`).join("")}</div><div class="cal-body" style="height:${hours * HOUR}px"><div class="cal-times" aria-hidden="true">${labels}</div>${columns}</div></div>`;
}

function agendaHtml(events) {
  return `<div class="agenda">${visibleDays(events).map((d) => {
    const list = events.filter((e) => e.days.includes(d)).sort((a, b) => toMin(a.start) - toMin(b.start));
    if (!list.length) return "";
    return `<section class="agenda-day" aria-label="${dayInfo(d).name}"><h3>${dayInfo(d).name}</h3><ul class="list">${list.map((e) => `<li><button class="row agenda-row${e.conflict ? " conflict" : ""}" type="button" data-action="event" data-event="${e.key}" data-key="ag-${e.key}-${d}"><span class="agenda-time">${esc(range(e.start, e.end))}</span>${dot(e.color, e.kind === "block")}<span class="row-main"><strong>${esc(e.title)}</strong>${e.kind === "class" ? `<small>${esc([e.label, `Section ${e.sectionLabel}`].filter(Boolean).join(" · "))}</small>` : ""}</span></button></li>`).join("")}</ul></section>`;
  }).join("")}</div>`;
}

const dot = (color, striped) => `<span class="dot tone-${color}${striped ? " striped" : ""}" aria-hidden="true"></span>`;

function colorButton(kind, entity) {
  const color = COLORS.find((c) => c.id === entity.color) || COLORS[0];
  return `<button class="dot-button tone-${color.id}${kind === "block" ? " striped" : ""}" type="button" data-action="open-color" data-kind="${kind}" data-id="${entity.id}" data-key="color-${entity.id}" aria-label="Color: ${color.name}"></button>`;
}

const seg = (action, options, value, label) => `<div class="seg" role="group" aria-label="${label}">${options.map(([v, text]) => `<button type="button" data-action="${action}" data-value="${v}" data-key="${action}-${v}" aria-pressed="${v === value}">${text}</button>`).join("")}</div>`;

function nav(actions = "") {
  const parent = app.stack[app.stack.length - 2];
  const label = parent ? (parent.screen === "plans" ? "Plans" : findPlan(parent.planId)?.name || "Back") : "";
  return `<header class="nav">${parent ? `<button class="nav-back" type="button" data-action="back" data-key="back"><span aria-hidden="true">‹</span>${esc(label)}</button>` : "<span></span>"}<div class="nav-actions">${actions}</div></header>`;
}

function starButton(starred) {
  return `<button class="nav-icon star" type="button" data-action="star" data-key="star" aria-pressed="${starred}" aria-label="Star">${starred ? "★" : "☆"}</button>`;
}

function orderedSchedules(plan, schedules) {
  const sorted = sortSchedules(schedules);
  const starred = plan.starred.map((k) => sorted.find((s) => s.key === k)).filter(Boolean);
  return [...starred, ...sorted.filter((s) => !plan.starred.includes(s.key))];
}

function summaryHtml(stats, picks) {
  return `<div class="chips"><span class="chip">${countText(stats.days, "day")} on campus</span><span class="chip">${gapsText(stats.gaps)}</span><span class="chip">${rangeMin(stats.first, stats.last)}</span></div><ul class="picks" aria-label="Sections">${picks.map((p) => `<li>${dot(p.color)}${esc(p.code)}-${esc(p.label)}</li>`).join("")}</ul>`;
}

function viewHtml(events, bands = []) {
  return `<div class="view-bar">${seg("view", [["week", "Week"], ["agenda", "Agenda"]], app.view.mode, "View")}<button class="icon-btn" type="button" data-action="calendar-options" data-key="cal-options" aria-label="Calendar options">⋯</button></div>${app.view.mode === "week" ? calendarHtml(events, bands) : agendaHtml(events)}`;
}

function finishText(a) {
  return a.incomplete.length === 1 ? `Finish ${a.incomplete[0].title}` : `Finish ${a.incomplete.length} items`;
}

function renderPlans() {
  const rows = app.store.plans.map((p) => `<li><button class="row" type="button" data-action="open-plan" data-plan="${p.id}" data-key="plan-${p.id}"><span class="row-main"><strong>${esc(p.name)}</strong><small>${countText(p.courses.length, "course")}</small></span><span class="chev" aria-hidden="true">›</span></button></li>`).join("");
  return `${nav(`<button class="nav-icon" type="button" data-action="new-plan" data-key="new-plan" aria-label="New plan">+</button>`)}<div class="content narrow"><h1 class="large-title screen-h" tabindex="-1">Plans</h1>${rows ? `<ul class="list">${rows}</ul>` : `<button class="btn btn-primary btn-block" type="button" data-action="new-plan">New plan</button>`}</div>`;
}

function cta(a) {
  if (a.status === "empty") return "";
  if (a.status === "incomplete") return `<div class="cta"><button class="btn btn-primary btn-block" type="button" data-action="finish" data-key="cta">${esc(finishText(a))}</button></div>`;
  if (a.status === "none") return `<div class="cta"><button class="btn btn-warn btn-block" type="button" data-action="open-schedules" data-key="cta">No schedule fits</button></div>`;
  const n = a.schedules.length;
  return `<div class="cta"><button class="btn btn-primary btn-block" type="button" data-action="open-schedules" data-key="cta">${n}${a.truncated ? "+" : ""} ${n === 1 ? "schedule fits" : "schedules fit"}</button></div>`;
}

function renderPlan(r) {
  const plan = findPlan(r.planId);
  const courseRows = plan.courses.map((c) => {
    const sub = [c.code.trim() && c.name.trim() ? c.name.trim() : "", countText(c.sections.length, "section")].filter(Boolean).join(" · ");
    return `<li><button class="row" type="button" data-action="open-course" data-id="${c.id}" data-key="course-${c.id}">${dot(c.color)}<span class="row-main"><strong>${esc(courseTitle(c))}</strong><small>${esc(sub)}</small></span>${courseComplete(c) ? "" : `<span class="flag">Incomplete</span>`}<span class="chev" aria-hidden="true">›</span></button></li>`;
  }).join("");
  const blockRows = plan.unavailable.map((u) => {
    const sub = u.times.filter(timeValid).map((t) => `${daysText(t.days)} ${range(t.start, t.end)}`).join(" · ");
    return `<li><button class="row" type="button" data-action="open-block" data-id="${u.id}" data-key="block-${u.id}">${dot(u.color, true)}<span class="row-main"><strong>${esc(blockTitle(u))}</strong>${sub ? `<small>${esc(sub)}</small>` : ""}</span>${blockComplete(u) ? "" : `<span class="flag">Incomplete</span>`}<span class="chev" aria-hidden="true">›</span></button></li>`;
  }).join("");
  return `${nav(`<button class="nav-icon" type="button" data-action="plan-menu" data-key="plan-menu" aria-label="Plan options">⋯</button>`)}<div class="content narrow">
    <h1 class="visually-hidden screen-h" tabindex="-1">${esc(plan.name)}</h1>
    <input class="title-input" data-field="plan-name" data-key="plan-name" value="${esc(plan.name)}" aria-label="Plan name" autocomplete="off" spellcheck="false">
    <h2 class="group-label">Courses</h2>
    <ul class="list">${courseRows}<li><button class="row row-add" type="button" data-action="add-course" data-key="add-course"><span class="plus" aria-hidden="true">+</span>Add course</button></li></ul>
    <h2 class="group-label">Unavailable</h2>
    <ul class="list">${blockRows}<li><button class="row row-add" type="button" data-action="add-block" data-key="add-block"><span class="plus" aria-hidden="true">+</span>Add time</button></li></ul>
    ${cta(analyze(plan))}
  </div>`;
}

function timeRow(t, { labelled, removable, visited }) {
  const invalid = Boolean(t.start && t.end && toMin(t.end) <= toMin(t.start));
  const miss = (empty) => (visited && empty ? "missing" : "");
  const removeLabel = labelled ? `Remove ${t.label || "meeting"}` : `Remove ${daysText(t.days) || "time"}`;
  const head = labelled || removable
    ? `<div class="time-row-head">${labelled ? `<input class="meeting-label" data-field="meeting-label" data-key="mlabel-${t.id}" value="${esc(t.label)}" placeholder="Meeting" aria-label="Meeting type" autocomplete="off">` : "<span></span>"}${removable ? `<button class="icon-btn" type="button" data-action="remove-time" data-key="remove-${t.id}" aria-label="${esc(removeLabel)}">×</button>` : ""}</div>`
    : "";
  return `<div class="time-row" data-time="${t.id}">${head}
    <div class="days ${miss(!t.days.length)}" role="group" aria-label="Days">${dayOrder().map((d) => `<button class="day" type="button" data-action="toggle-day" data-day="${d}" data-key="day-${t.id}-${d}" aria-pressed="${t.days.includes(d)}" aria-label="${dayInfo(d).name}">${dayInfo(d).short}</button>`).join("")}</div>
    <div class="times"><input class="${miss(!t.start)}" type="time" data-field="start" data-key="start-${t.id}" value="${esc(t.start)}" aria-label="Start time"><span aria-hidden="true">–</span><input class="${miss(!t.end)}" type="time" data-field="end" data-key="end-${t.id}" value="${esc(t.end)}" aria-label="End time" aria-invalid="${invalid}" aria-describedby="err-${t.id}"></div>
    <p class="field-error" id="err-${t.id}"${invalid ? "" : " hidden"}>End must be after start</p>
  </div>`;
}

function suggestHtml(plan, c) {
  let html = "";
  if (app.suggestFor === c.id) {
    const q = app.suggestTyped ? c.code.trim().toLowerCase() : "";
    const current = c.code.trim().toLowerCase();
    const taken = new Set(plan.courses.filter((x) => x.id !== c.id).map((x) => x.code.trim().toLowerCase()));
    const items = library(c.id).filter((e) => {
      const code = e.code.toLowerCase();
      if (taken.has(code) || (code === current && e.name === c.name.trim())) return false;
      return !q || code.includes(q) || e.name.toLowerCase().includes(q);
    }).slice(0, 6);
    if (items.length) html += `<ul class="suggest-list" aria-label="Previous courses">${items.map((e) => `<li><button class="suggest-row" type="button" data-action="pick-course" data-code="${esc(e.code)}" data-key="pick-${esc(e.code)}">${dot(e.color)}<strong>${esc(e.code)}</strong><span>${esc(e.name)}</span></button></li>`).join("")}</ul>`;
  }
  const offer = app.copyOffer;
  if (offer && offer.courseId === c.id) html += `<button class="chip chip-action" type="button" data-action="copy-sections" data-key="copy-sections">Copy ${countText(offer.entry.sections.length, "section")} from ${esc(offer.entry.from)}</button>`;
  return html;
}

function renderCourse(r) {
  const plan = findPlan(r.planId);
  const c = plan.courses.find((x) => x.id === r.courseId);
  const sections = c.sections.map((s) => `<section class="card" data-section="${s.id}" aria-label="Section ${esc(s.label)}">
      <div class="card-head"><label class="section-label">Section<input data-field="section-label" data-key="label-${s.id}" value="${esc(s.label)}" aria-label="Section number" autocomplete="off"></label><button class="icon-btn" type="button" data-action="section-menu" data-key="menu-${s.id}" aria-label="Section ${esc(s.label)} options">⋯</button></div>
      ${s.meetings.map((m) => timeRow(m, { labelled: true, removable: s.meetings.length > 1, visited: c.visited })).join("")}
      <button class="btn-text" type="button" data-action="add-meeting" data-key="add-meeting-${s.id}">+ Meeting</button>
    </section>`).join("");
  const unnamed = c.visited && !c.code.trim() && !c.name.trim();
  return `${nav()}<div class="content narrow">
    <h1 class="visually-hidden screen-h" tabindex="-1">${esc(courseTitle(c))}</h1>
    <div class="title-row">${colorButton("course", c)}<input class="title-input${unnamed ? " missing" : ""}" data-field="course-code" data-key="course-code" value="${esc(c.code)}" placeholder="Course code" aria-label="Course code" autocomplete="off" spellcheck="false" autocapitalize="characters"></div>
    <input class="subtitle-input" data-field="course-name" data-key="course-name" value="${esc(c.name)}" placeholder="Name" aria-label="Course name" autocomplete="off">
    <div id="suggest">${suggestHtml(plan, c)}</div>
    ${sections}
    <button class="btn-text" type="button" data-action="add-section" data-key="add-section">+ Section</button>
    <div><button class="btn-text danger delete-entry" type="button" data-action="delete-course" data-key="delete-course">Delete course</button></div>
  </div>`;
}

function renderBlock(r) {
  const plan = findPlan(r.planId);
  const u = plan.unavailable.find((x) => x.id === r.blockId);
  return `${nav()}<div class="content narrow">
    <h1 class="visually-hidden screen-h" tabindex="-1">${esc(blockTitle(u))}</h1>
    <div class="title-row">${colorButton("block", u)}<input class="title-input" data-field="block-name" data-key="block-name" value="${esc(u.name)}" placeholder="Work, practice…" aria-label="Name" autocomplete="off"></div>
    <div class="card spaced">${u.times.map((t) => timeRow(t, { labelled: false, removable: u.times.length > 1, visited: u.visited })).join("")}<button class="btn-text" type="button" data-action="add-time" data-key="add-time">+ Time</button></div>
    <div><button class="btn-text danger delete-entry" type="button" data-action="delete-block" data-key="delete-block">Delete</button></div>
  </div>`;
}

function reasonHtml(r) {
  const box = (title, lines) => `<div class="reason"><strong>${esc(title)}</strong>${lines.map((l) => `<span>${esc(l)}</span>`).join("")}</div>`;
  if (r.kind === "blocked") {
    const name = courseTitle(r.course);
    if (r.hits.length === 1) {
      const { hit } = r.hits[0];
      return box(`${name} overlaps ${blockTitle(hit.time.owner)}`, [overlapText(hit.meeting, hit.time)]);
    }
    return box(`Every ${name} section is blocked`, r.hits.map(({ section: s, hit }) => `Section ${s.label} · ${blockTitle(hit.time.owner)} · ${overlapText(hit.meeting, hit.time)}`));
  }
  if (r.kind === "pair") {
    const a = courseTitle(r.first);
    const b = courseTitle(r.second);
    return box(`${a} and ${b} always overlap`, r.clashes.slice(0, 4).map((x) => `${a}-${x.a.label} + ${b}-${x.b.label} · ${overlapText(x.hit.a, x.hit.b)}`));
  }
  return box("No combination of sections fits", []);
}

function renderSchedules(r) {
  const plan = findPlan(r.planId);
  const a = analyze(plan);
  if (a.status === "empty" || a.status === "incomplete") {
    app.events = [];
    return `${nav()}<div class="content"><h1 class="large-title screen-h" tabindex="-1">Schedules</h1><p class="muted">${esc(a.status === "empty" ? "Add a course" : finishText(a))}</p></div>`;
  }
  if (a.status === "none") {
    const { events, bands } = conflictEvents(a.reasons);
    app.events = events;
    return `${nav()}<div class="content"><div class="sched"><div class="sched-side"><h1 class="large-title screen-h" tabindex="-1">No schedule fits</h1>${a.reasons.map(reasonHtml).join("")}</div><div class="sched-main">${events.length ? viewHtml(events, bands) : ""}</div></div></div>`;
  }
  const list = orderedSchedules(plan, a.schedules);
  const index = Math.max(0, list.findIndex((s) => s.key === app.cursor[plan.id]));
  const current = list[index];
  app.cursor[plan.id] = current.key;
  app.events = scheduleEvents(plan, current.picks);
  const n = list.length;
  const more = a.truncated ? "+" : "";
  const side = `<h1 class="large-title screen-h" tabindex="-1">${n}${more} ${n === 1 ? "schedule fits" : "schedules fit"}</h1>
    ${n > 1 ? seg("sort", [["days", "Fewest days"], ["gaps", "Shortest gaps"]], app.view.sort, "Sort") : ""}
    ${n > 1 ? `<div class="pager"><button class="icon-btn" type="button" data-action="page" data-dir="-1" data-key="prev" aria-label="Previous schedule"${index === 0 ? " disabled" : ""}>‹</button><span>${index + 1} of ${n}${more}</span><button class="icon-btn" type="button" data-action="page" data-dir="1" data-key="next" aria-label="Next schedule"${index === n - 1 ? " disabled" : ""}>›</button></div>` : ""}
    ${summaryHtml(current, current.picks.map((p) => ({ code: courseTitle(p.course), label: p.section.label, color: p.course.color })))}`;
  return `${nav(starButton(plan.starred.includes(current.key)))}<div class="content"><div class="sched"><div class="sched-side">${side}</div><div class="sched-main">${viewHtml(app.events)}</div></div></div>`;
}

const screens = { plans: renderPlans, plan: renderPlan, course: renderCourse, block: renderBlock, schedules: renderSchedules };

function entityOf(kind, id) {
  const plan = currentPlan();
  return (kind === "course" ? plan?.courses : plan?.unavailable)?.find((x) => x.id === id);
}

function eventSheet(e) {
  const entity = entityOf(e.ref.type, e.ref.id);
  const head = entity ? colorButton(e.ref.type, entity) : `<span class="dot-spacer">${dot(e.color, e.kind === "block")}</span>`;
  return `<div class="sheet" role="dialog" aria-label="${esc(e.title)}"><span class="grabber" aria-hidden="true"></span>
    <div class="title-row">${head}<div class="sheet-title"><strong>${esc(e.title)}</strong>${e.name && e.name.trim() !== e.title ? `<small>${esc(e.name)}</small>` : ""}</div></div>
    ${e.kind === "class" ? `<p>${esc([`Section ${e.sectionLabel}`, e.label].filter(Boolean).join(" · "))}</p>` : ""}
    <p>${esc(`${daysText(e.days)} · ${range(e.start, e.end)}`)}</p>
    ${entity ? `<button class="btn btn-tinted btn-block" type="button" data-action="edit-ref" data-key="edit-ref">Edit</button>` : ""}
  </div>`;
}

function renderOverlay() {
  const s = app.sheet;
  let sheet = "";
  if (s?.type === "color") {
    const entity = entityOf(s.kind, s.id);
    sheet = `<div class="sheet" role="dialog" aria-label="Color"><span class="grabber" aria-hidden="true"></span><div class="swatches">${COLORS.map((c) => `<button class="swatch tone-${c.id}" type="button" data-action="pick-color" data-color="${c.id}" data-key="swatch-${c.id}" aria-label="${c.name}" aria-pressed="${entity?.color === c.id}"></button>`).join("")}</div></div>`;
  } else if (s?.type === "event") {
    sheet = eventSheet(s.event);
  } else if (s?.type === "calendar") {
    sheet = `<div class="sheet" role="dialog" aria-label="Calendar options"><span class="grabber" aria-hidden="true"></span>
      <div class="setting"><span id="weekends-label">Weekends</span><button class="switch" type="button" role="switch" data-action="toggle-weekends" data-key="weekends" aria-checked="${app.view.weekends}" aria-labelledby="weekends-label"></button></div>
      <div class="setting"><span>Week starts</span>${seg("week-start", [["mon", "Mon"], ["sun", "Sun"]], app.view.weekStart, "Week starts")}</div>
    </div>`;
  } else if (s?.type === "section") {
    const many = currentPlan().courses.find((c) => c.id === route().courseId).sections.length > 1;
    sheet = `<div class="sheet" role="dialog" aria-label="Section options"><span class="grabber" aria-hidden="true"></span><ul class="sheet-list"><li><button type="button" data-action="duplicate-section" data-key="duplicate-section">Duplicate section</button></li>${many ? `<li><button class="danger" type="button" data-action="delete-section" data-key="delete-section">Delete section</button></li>` : ""}</ul></div>`;
  } else if (s?.type === "plan") {
    sheet = `<div class="sheet" role="dialog" aria-label="Plan options"><span class="grabber" aria-hidden="true"></span><ul class="sheet-list"><li><button class="danger" type="button" data-action="delete-plan" data-key="delete-plan">Delete plan</button></li></ul></div>`;
  }
  const toastHtml = app.toast ? `<div class="toast"><span>${esc(app.toast.text)}</span>${app.toast.undo ? `<button type="button" data-action="undo" data-key="undo">Undo</button>` : ""}</div>` : "";
  overlayEl.innerHTML = `${sheet ? `<div class="backdrop" data-action="close-sheet"></div>${sheet}` : ""}${toastHtml}`;
}

function updateRail() {
  const theme = { auto: "Auto", dark: "Dark", light: "Light" }[app.theme];
  const themeButton = document.querySelector('[data-toggle="theme"]');
  themeButton.textContent = `Appearance: ${theme}`;
  themeButton.setAttribute("aria-pressed", String(app.theme !== "auto"));
  document.querySelector('[data-toggle="landscape"]').setAttribute("aria-pressed", String(app.landscape));
  document.querySelector('[data-toggle="largeText"]').setAttribute("aria-pressed", String(app.largeText));
  for (const button of document.querySelectorAll("[data-start]")) button.setAttribute("aria-pressed", String(button.dataset.start === app.mode));
  document.getElementById("rail-jumps").hidden = app.mode !== "returning";
}

function render() {
  const active = document.activeElement;
  const keepKey = active && (appEl.contains(active) || overlayEl.contains(active)) ? active.dataset.key : null;
  const selection = keepKey && typeof active.selectionStart === "number" ? [active.selectionStart, active.selectionEnd] : null;
  const scroll = appEl.scrollTop;
  if (route().planId && !currentPlan()) app.stack = [{ screen: "plans" }];
  appEl.innerHTML = screens[route().screen](route());
  renderOverlay();
  appEl.scrollTop = app.scrollTo ?? scroll;
  app.scrollTo = null;
  let target = null;
  for (const selector of [app.focus].flat().filter(Boolean)) {
    target = appEl.querySelector(selector) || overlayEl.querySelector(selector);
    if (target && !target.disabled) break;
    target = null;
  }
  if (!app.focus && keepKey) target = document.querySelector(`[data-key="${CSS.escape(keepKey)}"]`);
  app.focus = null;
  if (target && !target.disabled) {
    target.focus({ preventScroll: true });
    if (selection && target.setSelectionRange) {
      try {
        target.setSelectionRange(...selection);
      } catch {
        // Time inputs do not support text selection.
      }
    }
  }
  document.documentElement.dataset.theme = app.theme;
  document.documentElement.classList.toggle("large-text", app.largeText);
  phoneEl.classList.toggle("landscape", app.landscape);
  updateRail();
}

function announce(text) {
  statusEl.textContent = "";
  requestAnimationFrame(() => {
    statusEl.textContent = text;
  });
}

function toast(text, undo) {
  clearTimeout(app.toastTimer);
  app.toast = { text, undo };
  announce(text);
  app.toastTimer = setTimeout(() => {
    app.toast = null;
    renderOverlay();
  }, 6000);
  render();
}

function push(next, focus) {
  route().scroll = appEl.scrollTop;
  next.opener = document.activeElement?.dataset?.key;
  app.stack.push(next);
  app.sheet = null;
  app.focus = focus || ".screen-h";
  app.scrollTo = 0;
  render();
}

function leaveEditor(r) {
  const plan = findPlan(r.planId);
  if (!plan) return;
  if (r.screen === "course") {
    const c = plan.courses.find((x) => x.id === r.courseId);
    if (c && isEmptyCourse(c)) plan.courses.splice(plan.courses.indexOf(c), 1);
    else if (c) c.visited = true;
    app.suggestFor = null;
    app.copyOffer = null;
  }
  if (r.screen === "block") {
    const u = plan.unavailable.find((x) => x.id === r.blockId);
    if (u && isEmptyBlock(u)) plan.unavailable.splice(plan.unavailable.indexOf(u), 1);
    else if (u) u.visited = true;
  }
}

function pop() {
  if (app.stack.length < 2) return;
  const left = app.stack.pop();
  leaveEditor(left);
  app.sheet = null;
  app.scrollTo = route().scroll || 0;
  app.focus = [left.opener && `[data-key="${CSS.escape(left.opener)}"]`, ".screen-h"];
  render();
}

function openSheet(sheet) {
  app.sheetOpener = document.activeElement?.dataset?.key || null;
  app.sheet = sheet;
  app.focus = ".sheet button";
  render();
}

function closeSheet() {
  app.sheet = null;
  app.focus = app.sheetOpener ? `[data-key="${CSS.escape(app.sheetOpener)}"]` : null;
  render();
}

function targetOf(el) {
  const r = route();
  const plan = currentPlan();
  const timeId = el.closest("[data-time]")?.dataset.time;
  if (r.screen === "course") {
    const c = plan.courses.find((x) => x.id === r.courseId);
    const s = c.sections.find((x) => x.id === el.closest("[data-section]")?.dataset.section);
    return { plan, course: c, section: s, time: s?.meetings.find((m) => m.id === timeId), list: s?.meetings };
  }
  if (r.screen === "block") {
    const u = plan.unavailable.find((x) => x.id === r.blockId);
    return { plan, block: u, time: u.times.find((t) => t.id === timeId), list: u.times };
  }
  return { plan };
}

function nextLabel(sections) {
  const numbers = sections.map((s) => Number.parseInt(s.label, 10)).filter(Number.isFinite);
  return String((numbers.length ? Math.max(...numbers) : 0) + 1).padStart(2, "0");
}

const blankMeeting = (label = "") => ({ id: uid("m"), label, days: [], start: "", end: "" });
const copySection = (s, label) => ({ ...clone(s), id: uid("s"), label, meetings: s.meetings.map((m) => ({ ...clone(m), id: uid("m") })) });

function refreshSuggest(plan, c) {
  const box = document.getElementById("suggest");
  if (box) box.innerHTML = suggestHtml(plan, c);
}

function refreshRow(row, t) {
  const invalid = Boolean(t.start && t.end && toMin(t.end) <= toMin(t.start));
  row.querySelector('[data-field="end"]').setAttribute("aria-invalid", String(invalid));
  row.querySelector(".field-error").hidden = !invalid;
}

function jump(name) {
  const byName = (n) => app.store.plans.find((p) => p.name === n);
  const fall = byName("Fall 2026");
  const variant = byName("Fall 2026 (2)");
  const plans = { screen: "plans" };
  const at = (p) => ({ screen: "plan", planId: p.id });
  const chem = fall?.courses.find((c) => c.code === "CHEM 101");
  const work = fall?.unavailable.find((u) => u.name === "Work");
  const stacks = {
    plans: [plans],
    plan: fall && [plans, at(fall)],
    course: chem && [plans, at(fall), { screen: "course", planId: fall.id, courseId: chem.id }],
    unavailable: work && [plans, at(fall), { screen: "block", planId: fall.id, blockId: work.id }],
    schedules: fall && [plans, at(fall), { screen: "schedules", planId: fall.id }],
    "nothing-fits": variant && [plans, at(variant), { screen: "schedules", planId: variant.id }]
  };
  if (!stacks[name]) return;
  leaveEditor(route());
  app.stack = stacks[name];
  app.sheet = null;
  app.scrollTo = 0;
  app.focus = ".screen-h";
  render();
}

function pageBy(dir) {
  const plan = currentPlan();
  const list = orderedSchedules(plan, analyze(plan).schedules || []);
  const i = list.findIndex((s) => s.key === app.cursor[plan.id]);
  const next = Math.min(list.length - 1, Math.max(0, i + dir));
  app.cursor[plan.id] = list[next].key;
  app.focus = [next === 0 ? '[data-key="next"]' : next === list.length - 1 ? '[data-key="prev"]' : `[data-key="${dir < 0 ? "prev" : "next"}"]`];
  render();
}

const actions = {
  back: () => pop(),
  "new-plan": () => {
    const plan = { id: uid("p"), name: uniqueName(upcomingTerm()), courses: [], unavailable: [], starred: [] };
    app.store.plans.unshift(plan);
    push({ screen: "plan", planId: plan.id });
    announce(`Created ${plan.name}`);
  },
  "open-plan": (el) => push({ screen: "plan", planId: el.dataset.plan }),
  "plan-menu": () => openSheet({ type: "plan" }),
  "delete-plan": () => {
    const plans = app.store.plans;
    const i = plans.findIndex((p) => p.id === route().planId);
    const [plan] = plans.splice(i, 1);
    app.sheet = null;
    app.stack = [{ screen: "plans" }];
    app.focus = ".screen-h";
    toast(`Deleted ${plan.name}`, () => plans.splice(i, 0, plan));
  },
  "add-course": () => {
    const plan = currentPlan();
    const c = { id: uid("c"), code: "", name: "", color: COURSE_COLOR, sections: [{ id: uid("s"), label: "01", meetings: [blankMeeting("Lecture")] }] };
    plan.courses.push(c);
    app.suggestFor = c.id;
    app.suggestTyped = false;
    push({ screen: "course", planId: plan.id, courseId: c.id }, '[data-key="course-code"]');
  },
  "open-course": (el) => push({ screen: "course", planId: route().planId, courseId: el.dataset.id }),
  "add-block": () => {
    const plan = currentPlan();
    const u = { id: uid("u"), name: "", color: UNAVAILABLE_COLOR, times: [{ id: uid("t"), days: [], start: "", end: "" }] };
    plan.unavailable.push(u);
    push({ screen: "block", planId: plan.id, blockId: u.id }, '[data-key="block-name"]');
  },
  "open-block": (el) => push({ screen: "block", planId: route().planId, blockId: el.dataset.id }),
  "open-schedules": () => push({ screen: "schedules", planId: route().planId }),
  finish: () => {
    const item = analyze(currentPlan()).incomplete[0];
    push({ screen: item.screen, planId: route().planId, [item.key]: item.id });
  },
  "pick-course": (el) => {
    const { course: c } = targetOf(el);
    const entry = library(c.id).find((e) => e.code === el.dataset.code);
    Object.assign(c, { code: entry.code, name: entry.name, color: entry.color });
    app.copyOffer = entry.sections.length ? { courseId: c.id, entry } : null;
    app.suggestFor = null;
    app.focus = [app.copyOffer && '[data-key="copy-sections"]', '[data-key="course-name"]'];
    render();
    announce(`${entry.code} ${entry.name}`);
  },
  "copy-sections": (el) => {
    const { course: c } = targetOf(el);
    const before = c.sections;
    const copies = app.copyOffer.entry.sections.map((s) => copySection(s, s.label));
    c.sections = c.sections.every((s) => s.meetings.every(blankTime)) ? copies : [...c.sections, ...copies];
    app.copyOffer = null;
    app.focus = '[data-key="add-section"]';
    toast(`Copied ${countText(copies.length, "section")}`, () => {
      c.sections = before;
    });
  },
  "add-section": (el) => {
    const { course: c } = targetOf(el);
    const s = { id: uid("s"), label: nextLabel(c.sections), meetings: [blankMeeting("Lecture")] };
    c.sections.push(s);
    app.focus = `[data-key="day-${s.meetings[0].id}-${dayOrder()[0]}"]`;
    render();
  },
  "section-menu": (el) => openSheet({ type: "section", sectionId: el.closest("[data-section]").dataset.section }),
  "duplicate-section": () => {
    const c = currentPlan().courses.find((x) => x.id === route().courseId);
    const i = c.sections.findIndex((s) => s.id === app.sheet.sectionId);
    const copy = copySection(c.sections[i], nextLabel(c.sections));
    c.sections.splice(i + 1, 0, copy);
    app.sheet = null;
    app.focus = `[data-key="label-${copy.id}"]`;
    render();
    announce(`Section ${copy.label} added`);
  },
  "delete-section": () => {
    const c = currentPlan().courses.find((x) => x.id === route().courseId);
    const i = c.sections.findIndex((s) => s.id === app.sheet.sectionId);
    const [s] = c.sections.splice(i, 1);
    app.sheet = null;
    app.focus = '[data-key="add-section"]';
    toast(`Deleted section ${s.label}`, () => c.sections.splice(i, 0, s));
  },
  "add-meeting": (el) => {
    const { section: s } = targetOf(el);
    const m = blankMeeting();
    s.meetings.push(m);
    app.focus = `[data-key="mlabel-${m.id}"]`;
    render();
  },
  "add-time": (el) => {
    const { block: u } = targetOf(el);
    const t = { id: uid("t"), days: [], start: "", end: "" };
    u.times.push(t);
    app.focus = `[data-key="day-${t.id}-${dayOrder()[0]}"]`;
    render();
  },
  "remove-time": (el) => {
    const { list, time } = targetOf(el);
    if (list.length < 2) return;
    const i = list.indexOf(time);
    list.splice(i, 1);
    app.focus = ['[data-action="add-meeting"]', '[data-key="add-time"]'];
    toast(time.label ? `Removed ${time.label}` : "Removed", () => list.splice(i, 0, time));
  },
  "toggle-day": (el) => {
    const { time } = targetOf(el);
    const d = el.dataset.day;
    time.days = time.days.includes(d) ? time.days.filter((x) => x !== d) : [...time.days, d];
    render();
  },
  "delete-course": () => {
    const plan = currentPlan();
    const i = plan.courses.findIndex((c) => c.id === route().courseId);
    const [c] = plan.courses.splice(i, 1);
    app.stack.pop();
    app.suggestFor = null;
    app.copyOffer = null;
    app.focus = '[data-key="add-course"]';
    toast(`Deleted ${courseTitle(c)}`, () => plan.courses.splice(i, 0, c));
  },
  "delete-block": () => {
    const plan = currentPlan();
    const i = plan.unavailable.findIndex((u) => u.id === route().blockId);
    const [u] = plan.unavailable.splice(i, 1);
    app.stack.pop();
    app.focus = '[data-key="add-block"]';
    toast(`Deleted ${blockTitle(u)}`, () => plan.unavailable.splice(i, 0, u));
  },
  "open-color": (el) => openSheet({ type: "color", kind: el.dataset.kind, id: el.dataset.id }),
  "pick-color": (el) => {
    const entity = entityOf(app.sheet.kind, app.sheet.id);
    entity.color = el.dataset.color;
    announce(`Color: ${COLORS.find((c) => c.id === entity.color).name}`);
    closeSheet();
  },
  sort: (el) => {
    app.view.sort = el.dataset.value;
    render();
  },
  page: (el) => pageBy(Number(el.dataset.dir)),
  view: (el) => {
    app.view.mode = el.dataset.value;
    render();
  },
  "calendar-options": () => openSheet({ type: "calendar" }),
  "toggle-weekends": () => {
    app.view.weekends = !app.view.weekends;
    render();
  },
  "week-start": (el) => {
    app.view.weekStart = el.dataset.value;
    render();
  },
  event: (el) => openSheet({ type: "event", event: app.events.find((e) => e.key === el.dataset.event) }),
  "edit-ref": () => {
    const { ref } = app.sheet.event;
    const planId = route().planId;
    app.sheet = null;
    push(ref.type === "course" ? { screen: "course", planId, courseId: ref.id } : { screen: "block", planId, blockId: ref.id });
  },
  star: () => {
    const plan = currentPlan();
    const key = app.cursor[plan.id];
    if (!key) return;
    const starred = plan.starred.includes(key);
    plan.starred = starred ? plan.starred.filter((k) => k !== key) : [...plan.starred, key];
    announce(starred ? "Unstarred" : "Starred");
    render();
  },
  "close-sheet": () => closeSheet(),
  undo: () => {
    const t = app.toast;
    clearTimeout(app.toastTimer);
    app.toast = null;
    t.undo();
    announce("Restored");
    render();
  }
};

document.addEventListener("click", (event) => {
  const el = event.target.closest("[data-action], [data-jump], [data-toggle], [data-rail], [data-start]");
  if (!el || el.disabled) return;
  if (el.dataset.jump) {
    jump(el.dataset.jump);
  } else if (el.dataset.toggle) {
    if (el.dataset.toggle === "theme") app.theme = { auto: "dark", dark: "light", light: "auto" }[app.theme];
    else app[el.dataset.toggle] = !app[el.dataset.toggle];
    render();
  } else if (el.dataset.start) {
    start(el.dataset.start);
  } else if (el.dataset.rail === "reset") {
    start(app.mode);
  } else {
    actions[el.dataset.action]?.(el);
  }
});

for (const type of ["pointerdown", "mousedown"]) {
  document.addEventListener(type, (event) => {
    if (event.target.closest(".suggest-row")) event.preventDefault();
  });
}

document.addEventListener("input", (event) => {
  const el = event.target;
  const field = el.dataset?.field;
  if (!field) return;
  const t = targetOf(el);
  const value = el.value;
  if (field === "plan-name") t.plan.name = value;
  else if (field === "course-code") {
    t.course.code = value;
    app.suggestTyped = true;
    if (app.copyOffer && app.copyOffer.entry.code !== value.trim()) app.copyOffer = null;
    refreshSuggest(t.plan, t.course);
  } else if (field === "course-name") t.course.name = value;
  else if (field === "block-name") t.block.name = value;
  else if (field === "section-label") t.section.label = value;
  else if (field === "meeting-label") t.time.label = value;
  else if (field === "start" || field === "end") {
    t.time[field] = value;
    refreshRow(el.closest(".time-row"), t.time);
  }
  if (value) el.classList.remove("missing");
});

document.addEventListener("focusin", (event) => {
  const field = event.target.dataset?.field;
  if (field === "plan-name") app.nameBefore = event.target.value;
  if (field === "course-code") {
    const t = targetOf(event.target);
    app.suggestFor = t.course.id;
    app.suggestTyped = false;
    refreshSuggest(t.plan, t.course);
  }
});

document.addEventListener("focusout", (event) => {
  const el = event.target;
  const field = el.dataset?.field;
  if (field === "plan-name" && !el.value.trim()) {
    const plan = currentPlan();
    plan.name = app.nameBefore.trim() || uniqueName(upcomingTerm());
    el.value = plan.name;
  }
  if (field === "course-code") {
    setTimeout(() => {
      if (route().screen !== "course" || document.activeElement?.closest?.("#suggest")) return;
      const t = targetOf(el);
      if (!t.course) return;
      app.suggestFor = null;
      refreshSuggest(t.plan, t.course);
    }, 0);
  }
});

function start(mode) {
  app.mode = mode;
  app.store = seedStore(mode);
  app.stack = [{ screen: "plans" }];
  app.cursor = {};
  app.sheet = null;
  app.toast = null;
  app.suggestFor = null;
  app.copyOffer = null;
  app.scrollTo = 0;
  app.focus = ".screen-h";
  if (!app.store.plans.length) {
    const plan = { id: uid("p"), name: uniqueName(upcomingTerm()), courses: [], unavailable: [], starred: [] };
    app.store.plans.push(plan);
    app.stack.push({ screen: "plan", planId: plan.id });
  }
  render();
}

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && app.sheet) closeSheet();
  if (event.key === "Enter" && event.target.matches?.(".title-input, .subtitle-input")) event.target.blur();
});

start("new");
