//
//  Section.cpp
//  
//
//  Created by Ethan Blagg on 11/7/19.
//

#include "Section.hpp"

bool Section::operator == (const Section &right) {
    bool status = true;
    if(course != right.course ||
       startTime != right.startTime ||
       endTime != right.endTime) {
        
        status = false;
        
    } else {
        for (int i = 0; i < sizeof(days)/sizeof(bool); i++) {
            if (days[i] != right.days[i]) {
                status = false;
            } // if
        } // for
    } // if else
    
    // didn't find any differences then just return status as true
    return status;
}


void Section::setDays(string d) {
    char validDays[] = {'M','T','W','R','F'};  // possible days for classes
    int i = 0;
    
    //cout << d << endl; // print d
    for ( ; i < sizeof(validDays)/sizeof(char); i++) {   // check if each day is in d
        size_t found = d.find(validDays[i]);
        if ( found != string::npos ) { // npos indicates nothing was found
            days[i] = 1;    // day found
        }
        else {
            days[i] = 0;    // day not found
        }
        //cout << days[i]; // print boolean array
    } // for
    
    
} // setDays



string Section::getDays() const {
    string retDays = "";
    char validDays[] = {'M','T','W','R','F'};  // possible days for classes
    int i = 0;
    
    for ( ; i < sizeof(days)/sizeof(bool); i++) { // loop through bool array
        if (days[i]) {
            retDays = retDays + validDays[i]; // add the day if matching
        }
    } // for
    
    return retDays;
} // getDays


int Section::str2time(string t) {
    // First remove the colon. Result is desired time, plus AM/PM
    size_t colonPos = t.find(':');
    uint32_t tm;
    
    if (colonPos != string::npos) {
        t.erase(colonPos, 1);
    }
    
    //TODO: remove spaces

    // Second, split the number and the alpha from each other
    string::size_type sz;       // alias of size_t
    tm = stoi(t,&sz);           // set the start time
    t.erase(0,sz);              // leave only the AM/PM
    //cout << startTime << " " << t << endl; // Debug

    // Make sure am/pm is upper case
    for (int i=0; i < t.length(); i++) {
        t[i] = toupper(t[i]);
    }
    // Adjust start time if need be (PM)
    if ((t.find("PM") != string::npos) && (tm < 1200)) {
        tm += 1200;      // pm for 24 hour clock
    }
    
    return tm;
}



void Section::printVector(vector<Section> &s) {
    for (auto & i : s) {
        cout << i.getCourse() << " "
             << i.getDays() << " "
             << i.getStartTime() << " "
             << i.getEndTime() << " "
             << endl;
    }
}


void Section::print() {
        cout << getCourse() << " "
             << getDays() << " "
             << getStartTime() << " "
    << getEndTime() << " ";
}


bool Section::hasConflictWith(Section & s) {
    bool conflict = false;
    
    // For a conflict to occur, sections must have at least 1 day in common
    if (hasCommonDay(s)) {
        // Check for overlapping times here
        if (startTime >= s.getStartTime() && startTime <= s.getEndTime()) {
            conflict = true;
            cout << "Conflict1: ";
            print();
            cout << " | ";
            s.print();
            cout << endl;
        }
        else if (endTime >= s.getStartTime() && endTime <= s.getEndTime()) {
            conflict = true;
            cout << "Conflict2: ";
            print();
            cout << " | ";
            s.print();
            cout << endl;
        } // if else overlapping times
        
    } // if have common day
    
    // TODO: what if one course starts before and ends after another?? check that.
    return conflict;
}


bool Section::hasCommonDay(Section & s) {
    bool dayInCommon = false;
    
    for (int i = 0; i < sizeof(days)/sizeof(bool); i++) {
        if (days[i] && s.days[i]) {
            dayInCommon = true;
        }
    }
    return dayInCommon;
}
