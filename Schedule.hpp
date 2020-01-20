//
//  Schedule.hpp
//  
//
//  Created by Ethan Blagg on 11/6/19.
//

#ifndef Schedule_hpp
#define Schedule_hpp

#pragma once

#include "Section.hpp"
#include "Course.hpp"

#include <stdio.h>
#include <iostream>
#include <string>
#include <fstream>
#include <string>
#include <vector>
#include <cctype>
#include "nlohmann/json.hpp"    // https://github.com/nlohmann/json#stl-like-access
                                // https://nlohmann.github.io/json/index.html


class Schedule {

private:
    vector<Section> allSections;        // to hold all sections found
    vector<Course> courses;             // holds course ids
    vector<vector<Section>> schedules;  // holds possible schedules
    bool allowRepeatSections = false;
    
public:
    // Constructor
    Schedule() {
        cout << "New Schedule Created\n";
    }
    
    // Destructor
    ~Schedule() {
        // delete only necessary for "new"?
    }
    
    // Accessors
    void printSections();
    void printCourses();
    void printCoursesDetailed();
    void printScheduleToConsole();
    
    // Mutators
    void setCourses();  // create courses vector from all sections list
    void addCourse(string);
    void addCourse(Section);
    
    
    // Member Functions
    void createSectionsFromFile(fstream &);
    void createScheduleList();
    void checkNextCourse(int, vector<Section> &);
    bool isConflicting(vector<Section> &, Section &);
    bool isRepeatSection(Section&) const;
    void findNonconflictingSchedules();
    void writeToFile(fstream &);
    

};


#endif /* Schedule_hpp */
