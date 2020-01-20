//
//  Schedule.cpp
//  
//
//  Created by Ethan Blagg on 11/6/19.
//

#include "Schedule.hpp"




// for convenience
using json = nlohmann::json;


void Schedule::createSectionsFromFile(fstream& file) {
    
    Section sectionBuf;       // read sections from json file into buffer
    json jsonSections;    // json file object
    
    if (!file.fail()) {
        file >> jsonSections; // get json object from file
    }
    else { // failed to open file
        cout << "ERROR: Failed to open file";
        exit(0);
    }
    
    // create Section objects from json file
    for (int i = 0; i < jsonSections["courses"].size(); i++) {
        //cout << i << "......\n";      // Debug
        sectionBuf.setCourse(jsonSections["courses"][i]["course"]);
        sectionBuf.setDays(jsonSections["courses"][i]["days"]);
        sectionBuf.setStartTime(jsonSections["courses"][i]["start"]);
        sectionBuf.setEndTime(jsonSections["courses"][i]["end"]);
        
        // Add section to Sections list if not a repeat
        if (allowRepeatSections) {              // dont care if repeated
            allSections.push_back(sectionBuf);
        }
        else if (!isRepeatSection(sectionBuf)) {// care if repeat, and not repeat
            allSections.push_back(sectionBuf);
        }                                       // otherwise don't push
    } // for
    
} // getSectionsFromFile

bool Schedule::isRepeatSection(Section& sec) const {
    bool isrepeat = false;
    for (Section s : allSections) {
        if (sec == s) {
            isrepeat = true;
        } // if
    } // for
    return isrepeat;
}


void Schedule::printSections() {
    for (Section sec: allSections) {
        cout << sec.getCourse() << " "
             << sec.getDays() << " "
             << sec.getStartTime() << " "
             << sec.getEndTime() << " "
             << endl;
    }
}

void Schedule::setCourses() {
    // Create a vector of distinct courses (use Courses vector)
    for (Section sec: allSections) {
        
        bool match = false;

        for (int i = 0; i < courses.size(); i++) {
            
            if ( !sec.getCourse().compare(courses[i].getCourse()) ) {
                // course already exists (strings equal)
                int numSecs = courses[i].addSection(sec);
                match = true;
            }
        }
        
        if (!match) { // Need to add the course!
            addCourse(sec);
        }
    } // for sec
} // setCourses


void Schedule::addCourse(string cID) {
    Course temp(cID);
    courses.push_back(temp);
}

void Schedule::addCourse(Section sec) {
    Course temp(sec);
    courses.push_back(temp);
}
                
void Schedule::printCourses() {
    for (Course c: courses) {
        cout << c.getCourse() << endl;
    }
}

void Schedule::printCoursesDetailed() {
    for (Course c: courses) {
        cout << c.getCourse() << endl;
        for (Section s: c.getSections()) {
            cout << "\t" << s.getDays()
                 << " " << s.getStartTime()
                 << " - " << s.getEndTime() << endl;
        } // for s
    } // for c
}

void Schedule::findNonconflictingSchedules() {
    
    //cout << "\nIn Schedule::findNonconflictingSchedules()\n";
    int courseNum = 0;          // initial course
    vector<Section> initSec;    // empty section to get started
    checkNextCourse(courseNum, initSec);

}

// NOTE: pretty sure the schedule candidate stuff isn't correct
//       ...when/where should a new one be created?
void Schedule::checkNextCourse(int courseNum, vector<Section> &scheduleCandidate) {
    
    //cout << "\n\n\n**** checkNextCourse()\tcourseNum="<< courseNum << "/" << courses.size()-1 << "\n"; // Debug
    // go through each section in the course
    for (int i = 0; i < courses[courseNum].getSections().size(); i++) {
        // Create a new Schedule Candidate (copy of current) and continue
        // This is likely not the proper way to do this...fix later
        vector<Section> newSchedCand = scheduleCandidate;
//        vector<Section> newSchedCand;
//        for (int i=0; i < scheduleCandidate.size(); i++) {
//            newSchedCand.push_back(scheduleCandidate[i]);
//        }
        
        
        //cout << "Printing schedule candidate size=" << newSchedCand.size()
        //     << "  courseNum=" << courseNum << "  section=" << i
        //     << "  id=" << courses[courseNum].getSections()[i].getCourse()<< "\n";
        //Section::printVector(newSchedCand);
        
        // check if times conflict
        if (!isConflicting(newSchedCand, courses[courseNum].getSections()[i]) ) {
            
            // DONT CONFLICT - Add the section to the candidate
            newSchedCand.push_back(courses[courseNum].getSections()[i]);
            
            // Add the candidate to the schedule if in last course
            if (courseNum == courses.size() - 1 ) {
                //cout << "\tPushing schedule candidate\n"; Debug
                schedules.push_back(newSchedCand);
                //Section::printVector(newSchedCand); // debug
            }
            else { // otherwise go to next course (courseNum) if it exists
                // cout << "\tGoing to next course\n"; // Debug
                checkNextCourse(courseNum+1, newSchedCand);
            } // if else
        } // if conflicting
        
    } // for
    
} //


bool Schedule::isConflicting(vector<Section> &sVec, Section &s) {
    bool conflict = false;

    // Set conflict flag if a start time is during another section
    for(Section i: sVec) {
        if (s.hasConflictWith(i) ) {
            conflict = true;
        }
    } // for
    
    return conflict;
}


void Schedule::writeToFile(fstream &file) {
    json j;    // json file object to write to
    json jbuf;
    
    for (int i = 0; i < schedules.size(); i++) {
        
        for (int s = 0; s < schedules[i].size(); s++) {
            //cout << "    " << schedules[i][s].getCourse() << endl; // debug
            jbuf[s]["course"] = schedules[i][s].getCourse();
            jbuf[s]["days"] = schedules[i][s].getDays();
            jbuf[s]["start"] = schedules[i][s].getStartTime();
            jbuf[s]["end"] = schedules[i][s].getEndTime();
        }
        j[i] = jbuf;
    }

    if (!file.fail()) {
        file << j; // get json object from file
    }
    else { // failed to open file
        cout << "ERROR: Failed to open file";
        exit(0);
    }
}



void Schedule::printScheduleToConsole() {
    int perm = 1;
    
    for (vector<Section> s : schedules) {
    //for (int i = 0; i < schedules.size(); i++) {
        cout << "Schedule # " << perm << endl;
        Section::printVector(s);
        cout << endl;
        perm++;
    }
}

