# IMGD/CS 420x: Graphical Simulation of Physical Systems

This course focuses on the digital simulation of physical systems and strategies for interactive representation. Topics include:

- Parallel computing on graphics processing units (GPUs)  
- Realtime graphics techniques  
- The history of analog interactive visuals  
- Interaction techniques for controlling digital simulations  

Students will explore digital simulations of real world phenonmenon, such as chemical diffusion models, models of artifical life, fluid simulations, and video feedback. The class is designed to encourage both technical and aesthetic exploration.  

All students will be expected to maintain a course website that contains links to all assignments. Videos should be posted to "permanent" locations (Vimeo, YouTube etc.) and embedded / linked in your course website. Details on this website can be found in the [onboarding assignment](./onboarding.md). 

Assignments and examples for this class will primarily use GLSL / JavaScript, however, other environments and systems for GPU programming will be discussed and may be suitable for final projects.

## Course Outline

This is an experimental course; as such this outline is subject to change. I am happy to make minor additions if there are related topics of interest that are not mentioned here... please let me know!  

### Week 1: Getting Started / Review
1/12 - [*Basic Intro to WebGL / Shader programmming*](./notes.day1.intro_to_shaders.md) Assignment:  
  - Complete the [onboarding](./onboarding.md). Due 1/20.  

1/13 - *GLSL Live Coding and History-Visual Music*.  Assignments:  
  - Read / experiment with [The Book of Shaders](http://thebookofshaders.com) up through the lesson on [Noise](https://thebookofshaders.com/11/).  
  - Complete the [Shader Live Coding Assignment](./A1.shader_live_coding.md) also due 1/20.  

### Week 2: History-Analog synthesis and video feedback
1/17 - Martin Luther King Jr. Day - NO CLASS  

1/20 -  *Video Synthesis History and Video Processing*.  
  - [Analog synthesis history](./notes.day3.md).
  - [Using textures, images, andd live video input](./notes.day4.md)  

### Week 3: Automata, Reaction Diffusion, and Rendering to Texture
1/24 - Rendering to Texture, 1D / 2D Automata, Game of Life  

1/27 - Reaction Diffusion
 
### Week 4: Perlin Flows and Modular GLSL,
1/31 -  [Modular GLSL](./notes.day8.md). Assignments: 
  - [Simulation](./simulation.md) due 2/20. 
  - Read the chapters on [Cellular Noise](https://thebookofshaders.com/12/) and [Fractal Brownian Motion](https://thebookofshaders.com/13/) in the Book of Shaders.  

### Week 5: Interaction in Digital Arts

### Week 6: Other ways to tame the GPU: OpenCL + WebGPU + CUDA

### Week 7: ???


### Week 8: Final Project Presentations &amp; Wrapup  
3/2 - Wrap-up, preliminary final project critiques  
3/5 - Final Project Presentations  

# Grades
Your course grade comes from three parts:

Assignments (55%)  
Final Project (35%)  
Quizzes, in-class assignments, attendance (10%)  

There will most likely be 4–5 assignments in the course in addition to the final project. I reserve the right to adjust the above if needed. 

I'm guessing everyone will need to turn in at least one assignment late this term given our current situation; just let me know! I don't want anyone getting too far behind in the class as the technical material is sequential, but I'll do my best to help you figure out a reasonable schedule for completing your coursework.

# Attendance
Attendance is required. Please notify the instructor in advance over Discord if you must miss class. All classes will be recorded for asynchronous viewing / review.

# Academic Integrity
The goal of this class is to both create aesthetically interesting content and understand the code used to create it. In order to understand the code, you need to author it yourself. Copying and pasting code is not allowed in this class, unless explicitly stated by the instructor. If you have a question about this, ask the instructor!!

Collaboration is encouraged in this class. There are many ways in which you can assist others without giving them code and answers. Providing low-level implemetation details (small code fragments that contribute to, but don't complete on their own, major portions of assignments) is great. For example, telling a classmate that they need to use the `smoothstep()` function in GLSL and showing them how to call it.
