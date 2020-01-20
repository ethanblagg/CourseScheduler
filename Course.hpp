//
//  Course.hpp
//  
//
//  Created by Ethan Blagg on 11/2/19.
//

#ifndef Course_hpp
#define Course_hpp

#include "Section.hpp"
#include <string>
#include <vector>

using namespace std;

class Course {
private:
    vector<Section> sections;   // sections for given course
    string course;              // holds Course id (BIO1000)
    
public:
    Course (string c) {
        course = c; // strcpy??
    }
    
    Course (Section sec) {
        sections.push_back(sec);
        course = sec.getCourse();
    }
    
    // Accessors
    string getCourse() const {return course;}
    vector<Section> & getSections() {return sections;}
    int getNumSections() {return sections.size();}
    
    // Mutators
    int addSection(Section s) {
        sections.push_back(s);
        return sections.size();
    }
    
};


#endif /* Course_hpp */
