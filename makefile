# makefile for ScheduleHelper

# -I tell to look in current folder

CPPFLAGS +="-I./include/"
CPPFLAGS +="-I./"
CPPVER   +="-std=c++11"

maintest:	main.cpp schedule.o course.o section.o
	g++ $(CPPVER) $(CPPFLAGS) -o maintest main.cpp schedule.o course.o section.o

schedule.o:	Schedule.cpp Schedule.hpp course.o section.o
	g++ $(CPPVER) $(CPPFLAGS) -c Schedule.cpp Schedule.hpp

course.o:	Course.cpp Course.hpp section.o
	g++ $(CPPVER) $(CPPFLAGS) -c Course.cpp Course.hpp

section.o:	Section.cpp Section.hpp
	g++ $(CPPVER) $(CPPFLAGS) -c Section.cpp

clean:
	rm *.o *.gch maintest


