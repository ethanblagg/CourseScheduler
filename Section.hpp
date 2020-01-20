 //
//  Section.hpp
//  
//
//  Created by Ethan Blagg on 11/7/19.
//

#ifndef Section_hpp
#define Section_hpp

#pragma once

#include <stdio.h>
#include <string>
#include <cctype>   // isalpha
#include <iostream>
#include <vector>

using namespace std;

class Section;

class Section {
    
private:
    string course;  // holds the section id (ie CHEM1001)
    bool days[5];   // holds days class is held
    int startTime;
    int endTime;
    
public:
    // Constructor
    Section() {
        cout << "New Section Created\n";
    }
    
    // Setters
    void setCourse(string c) {course = c;}
    void setDays(string d);
    void setStartTime(string t) {startTime = str2time(t);}
    void setEndTime(string t) {endTime = str2time(t);}
    
    // Getters
    string getCourse() const {return course;}
    string getDays() const;
    int getStartTime() const {return startTime;};
    int getEndTime() const {return endTime;};
    
    // Member Function
    int str2time(string t);
    static void printVector (vector<Section> &);
    void print();
    bool hasConflictWith(Section &);
    bool hasCommonDay(Section &);
    
    // Overloaded Operator Functions
    bool operator == (const Section &right);
};

#endif /* Section_hpp */
