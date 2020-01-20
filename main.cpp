//
//  main.cpp
//  
//
//  Created by Ethan Blagg on 11/6/19.
//

#include <stdio.h>
#include "Schedule.hpp"
#include "fstream"


int main() {
    
    // file to be read (gather classes/sections)
    fstream infile ("cls.json", ios::in);
    fstream outfile("sch.json", ios::out);
    
    Schedule schedule;
    
    schedule.createSectionsFromFile(infile);
    //schedule.printSections();
    schedule.setCourses();      // create a list of courses w/ secs
    schedule.printCoursesDetailed();
    schedule.findNonconflictingSchedules();
    schedule.writeToFile(outfile);
    cout << endl;
    schedule.printScheduleToConsole();
    
    return 0;
}
