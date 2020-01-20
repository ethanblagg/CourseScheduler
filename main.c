//
// main.c
// classorg
// Ethan Blagg
// 9-15-18
//
// This program will take user input classes, schedules then provide
// a list of potential schedules where classes align.

#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

#define FIELD_SIZE 11       // FIELD_SIZE is the MAX number of
#define MAX_RECORDS 50      // Max number of records
#define MAX_COURSES 10
#define MAX_SECTIONS 10
#define FIRST_CLASS_TIME 800
#define PROJ_PWD "/Users/ethanblagg/SynologyDrive/Documents/Projects/CourseCombos/CourseCombos/"
//#define SECTIONS_FILE "/Users/ethanblagg/Documents/workspace/CourseCombos/CourseCombos/cls.txt"
#define SEC_TXT "cls.txt"
#define SECTIONS_FILE PROJ_PWD SEC_TXT
#define OUT_TXT "schedperms.txt"
//#define OUTPUT_FILE "/Users/ethanblagg/Documents/workspace/CourseCombos/CourseCombos/schedperms.txt"
#define OUTPUT_FILE PROJ_PWD OUT_TXT

// Structures and types
typedef struct {
    char course_id[FIELD_SIZE];
    char days[FIELD_SIZE];
    char start[FIELD_SIZE];
    char end[FIELD_SIZE];
} section;

typedef struct {
    char course_id[FIELD_SIZE];
    section section[MAX_SECTIONS];
    int sections;
} courseID;


typedef struct {
    section sections[MAX_COURSES];
} course_combo;



// Prototypes
int copy_courseID_array (courseID *to, courseID *from, int num_courses, int num_sections);
int print_scheds (courseID *courses, int num_courses, FILE *output);
int print_scheds_helper (courseID *courses, int num_courses, course_combo *course_combos, int k, FILE *output);
void fill_course_array ( FILE * file_ptr, courseID courses[], int num_courses, int num_sections, int *start_indices);
int get_num_sections (FILE *file_ptr);
int get_num_courses_start_indices ( FILE *file_ptr, int num_sections, int *start_indices);
int is_overlapping_combo (course_combo combo, int num_courses);


// ************************************************************************************************************
// ************************************************************************************************************



int main(int argc, const char * argv[]) {
    
    // use the file cls.txt as input. found in ./
    // Format is as follows
    // CLASS   [MTWRF]  Start  End
    // CS2060  TRF      800    925
    
    courseID temp_courses[MAX_COURSES] = {0};       // Init to zeros, so data is clean
    const char F[] = SECTIONS_FILE; // Filename to be opened
    const char O[] = OUTPUT_FILE;   // Filename for output
    FILE *file_ptr;                 // Pointer to file
    FILE *output;                   // Pointer to output file
    int start_indices[MAX_SECTIONS] = {0};
    
    
    // Open the file
    file_ptr = fopen(F, "r");
    
    if ( file_ptr == NULL ) {
        printf("%s could not be opened", F);
        printf("The error is - %s\n", strerror(errno));
    }
    else {
        
        // Open the output file
        output = fopen(O, "w");
        if (output == NULL ) {
            printf("%s could not be opened", F);
            printf("The error is - %s\n", strerror(errno));
        }
        
        // Get the number of sections and courses
        int num_sections = get_num_sections (file_ptr);
        int num_courses  = get_num_courses_start_indices (file_ptr, num_sections, start_indices);
        
        // Fill the courses structure
        fill_course_array (file_ptr, temp_courses, num_courses, num_sections, start_indices);

        // copying to courses is not working for now, so I'll just use the temp
        print_scheds(temp_courses, num_courses, output);
        
        
        
    } // else (file is open)
    
    fclose(file_ptr);
    fclose(output);
    
    printf("\n\nSuck a dick, bitch!\n");
    
} // main






int copy_courseID_array (courseID *to, courseID *from, int num_courses, int num_sections) {
    // Copies arrays of classrecords
    
    for (int i = 0; i < num_courses; i++ ) {
        // Iterate through each course
        
        for (int j = 0; j < MAX_SECTIONS; j++) {
            
            // Copy all the strings in the classrecord structure
            memcpy( to[i].section[j].days,  from[i].section[j].days,  FIELD_SIZE);
            memcpy( to[i].section[j].start, from[i].section[j].start, FIELD_SIZE);
            memcpy( to[i].section[j].end,   from[i].section[j].end,   FIELD_SIZE);
            
        } // for j
    } // for i
    
    return num_sections;
    
} // copy_classrecord





int print_scheds (courseID *courses, int num_courses, FILE *output) {
    // Print the possible schedules that don't conflict
    // Each printed schedule should contain no duplicat class ID's (classes[n].class]
    // This function ASSUMES the classrecord is sorted according to class ID
    
    // I'll use a recursive solution for now, as it is easiest to implement
    // https://stackoverflow.com/questions/2836087/generating-all-permutations-of-character-combinations-when-of-arrays-and-lengt
    
    // Calc the necessary length of course_combos, declared below
    int n = 1;
    for (int i = 0; i < num_courses; i++) {
        n = n * courses[i].sections;
    } // for i
    printf("n = %d", n);
    
    // array of courseID's to hold all the combos of courses
    course_combo course_combo_array[n];
    
    // zero out the memory for this.
    memset(course_combo_array, 0, sizeof (course_combo_array));
    
    // print the schedules and return # of schedules that don't have overlaps
    int working_combinations = print_scheds_helper(courses, num_courses, course_combo_array, 0, output);
    
    printf("\nWorking combinations: %d", working_combinations);
    printf(" / %d", n);
    
    
    return 0;
    
} // print_scheds





int print_scheds_helper (courseID *courses, int num_courses, course_combo *course_combos, int k, FILE *output) {
    // Recursion helper for printing schedules
    // Returns an array of schedules
    static int combo_ctr = 0;
    static int combinations = 0;
    static int working_combinations = 0;
    
    if ( k == num_courses) {
    // A combo has been created, so
        
        
        if (!is_overlapping_combo(course_combos[combo_ctr], num_courses) ) {
        // Not overlapping
        
            printf("\n[  ");
            for (int i = 0; i < num_courses; i++) {
                
                // Print the working combo to the console
                printf("%s %s %s %s,\t", course_combos[combo_ctr].sections[i].course_id, course_combos[combo_ctr].sections[i].days,
                       course_combos[combo_ctr].sections[i].start, course_combos[combo_ctr].sections[i].end);
                
                // Print the working combo to a file
                fprintf(output, "%s %s %s %s\t", course_combos[combo_ctr].sections[i].course_id, course_combos[combo_ctr].sections[i].days,
                        course_combos[combo_ctr].sections[i].start, course_combos[combo_ctr].sections[i].end);
                
            } // for
            
            // Add a new line to output file
            fprintf(output, "\n" );
            ++working_combinations;
            
        } else {
        // ARE overlapping
            
            printf("\n[x ");
            for (int i = 0; i < num_courses; i++) {
                
                printf("%s %s %s %s,\t", course_combos[combo_ctr].sections[i].course_id, course_combos[combo_ctr].sections[i].days,
                       course_combos[combo_ctr].sections[i].start, course_combos[combo_ctr].sections[i].end);
            } // for
        
        } // if else <- overlapping
        
        // increase combinations (whether overlapping or not)
        ++combinations;
        
        
    } else {
        
        for (int i = 0; i < courses[k].sections; i++) {
            course_combos[combo_ctr].sections[k] = courses[k].section[i];
            print_scheds_helper(courses, num_courses, course_combos, k + 1, output);
            
        } // for
        
    } // for else
    
    //printf("Total combinations: %d", combinations);
    return working_combinations;
}





int is_overlapping_combo (course_combo combo, int num_courses) {
    
    int overlaps = 0;
    
    // create a times array, zero it
    int times[2][num_courses];
    memset(times, 0, sizeof(times));
    
    // Fix times to 24hr and fill times array
    for (int i = 0; i < num_courses; i++) {
        int start = atoi( combo.sections[i].start);
        int end   = atoi( combo.sections[i].end);
        
        if (start < FIRST_CLASS_TIME) {
            start += 1200;
        }
        if (end < FIRST_CLASS_TIME) {
            end += 1200;
        }
        
        times[0][i] = start;
        times[1][i] = end;
    } // for
    
    
    for (int i = 0; i < num_courses - 1; i++) {
        
        for (int j = i + 1; j < num_courses; j++) {
          
            if ( (times[0][i] >= times [0][j])  &&  (times[0][i] <= times[1][j]) ) {
            // There is overlap
                ++overlaps;
            } // if
            
        } // for j
        
    } // for i
    
    // return 0 if no overlaps
    return overlaps;
    
} // is_non_overlapping_combo






void fill_course_array ( FILE * file_ptr, courseID *courses, int num_courses, int num_sections, int *start_indices) {
    // Fill the courseID[] structure.
    
    //char *course_id[FIELD_SIZE];
    //char *days[FIELD_SIZE];
    //char *start[FIELD_SIZE];
    //char *end[FIELD_SIZE];
    
    for (int i = 0; i < num_courses; i++) {
        // Loop through courseID's
        
        int sec_ctr = 0;
        for (int j = start_indices[i]; j < start_indices[i+1]; j++) {
            
            // Loop through sections in each courseID, parse a line from file, fill a record, then print
            fscanf(file_ptr, "%s %s %s %s\n", courses[i].section[sec_ctr].course_id, courses[i].section[sec_ctr].days, courses[i].section[sec_ctr].start, courses[i].section[sec_ctr].end );
            
            memcpy(courses[i].course_id, courses[i].section[sec_ctr].course_id, FIELD_SIZE);
            
            
            printf("%s %s %s %s\n", courses[i].course_id, courses[i].section[sec_ctr].days, courses[i].section[sec_ctr].start, courses[i].section[sec_ctr].end );
            
            ++sec_ctr;
            
            courses[i].sections = sec_ctr;
            
        } // for j
        
    } // for i
    
} // fill_course_array







int get_num_sections (FILE *file_ptr) {
    // Gets number of lines in file
    
    FILE* temp_ptr = file_ptr;
    // ADD A CHECK TO STRIP ALL EMPTY LINES
    
    // RETURN 0 if none
    
    int lines = 0;
    char temp[101] = {0};
    
    while ( fgets(temp, 100, temp_ptr ) ) {
        
        ++lines;
        //printf("\nINSIDE: %p \t lines: %d", temp_ptr, lines);
        
    } // while
    
    // rewind the file_ptr to point at the beginning of the file for future use
    //rewind(file_ptr);
    
    //printf("\nAFTER REWIND: %p", file_ptr);
    
    rewind(file_ptr);
    
    return lines;
}




int get_num_courses_start_indices ( FILE *file_ptr, int num_sections, int *start_indices) {
    // Gets number of distince course ID's
    
    int num_courses = 0;
    char sections[MAX_RECORDS][FIELD_SIZE] = {0};
    char dummy[100] = {0};
    
    for (int i = 0; i < num_sections; i++) {
        fscanf(file_ptr, "%s %s %s %s\n", sections[i], dummy, dummy, dummy);
    }
    
    for (int i = 1; i < num_sections; i++) {
        
        if ( strcmp(sections[i-1], sections[i]) ) {
            // Strings are NOT equal
            
            ++num_courses;
            start_indices[num_courses] = i;
        } // if
        // Strings are equal
        
    } // for
    
    // Remember the last course
    ++num_courses;
    
    // Store the end index of the last course, after all the start indices.
    // THis is useful when filling the courses data structure
    start_indices[num_courses] = num_sections;
    // fill_ind...... for (int j = start_indices[i]; j < start_indices[i+1]; j++) {
    
    rewind(file_ptr);
    
    return num_courses;
    
    
} // get_num_courses
















/*
 int get_start_end_indices(course *classes, int num_records, int *start_array, int *end_array) {
 // Find the start and end index for each different class type (so it contains sections)
 // Create arrays of numbers with start and end indexes for each class type
 // So, for
 
 0  | CS2060 MWF 800 915
 1  | CS2060 MWF 925 1040
 2  | CS2060 MWF 305 420
 3  | CS2060 MWF 445 6
 4  | CS1450 TR 305 420
 5  | CS1450 MW 800 915
 6  | CS1450 MW 1215 130
 7  | MATH2350 TRF 800 915
 8  | MATH2350 TRF 305 420
 9  | PES1120 MWF 800 915
 10 | PES1120 TRF 800 915
 11 | PES1120 TRF 1040 1205
 // start_array would be [0, 4, 7, 9]
 // end_array   would be [3, 6, 8, 11]
 
 // Start with 0 classes
 int classes_ctr = 0;
 for ( size_t i = 0 ; i < num_records - 1; i++) {
 //
 //printf("\nclasses[%d].class = %s", i, classes[i].class);
 if ( strcmp(classes[i].class, classes[i+1].class) ) {
 // Strings are NOT equal
 // Set the necessary end and start values for the current and next class
 
 end_array[classes_ctr] = i;
 
 ++classes_ctr;
 start_array[classes_ctr] = i + 1;
 
 }
 // Strings are equal
 
 } // for
 
 // Set the last end_array value (First start_array value was initialized to 0)
 end_array[classes_ctr] = num_records - 1 ;
 
 // Increase because we were using it as an index
 ++classes_ctr;
 
 return classes_ctr;
 
 } // get_start_end_indices
 
 */






/*
 int num_first ( classrecord *classes, size_t num_records) {
 // Find number of records that are of first class
 int num_first = 1;
 for ( size_t i = 0; i < num_records; i++) {
 //
 if ( strcmp(classes[i].class, classes[i+1].class) ) {
 // if strings are not equal, exit loop
 i = num_records + 1;
 
 }else {
 // increase counter
 ++num_first;
 
 } // if-else
 } // for
 
 printf("\nNumber of first record: %d", num_first);
 
 return num_first;
 } // num_first
 */

