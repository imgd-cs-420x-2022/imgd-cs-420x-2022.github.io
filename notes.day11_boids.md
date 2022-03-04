# Towards Boids on the GPU

This tutorial aims to get us at least part of the way towards implementing the [Boids (aka Flocking) algorithm](http://www.kfish.org/boids/pseudocode.html), originally presented [in a classic paper that has been cited over 11000 times](https://www.google.com/url?sa=t&rct=j&q=&esrc=s&source=web&cd=3&cad=rja&uact=8&ved=2ahUKEwiqy5OP_tPoAhWDuJ4KHdqmDH4QFjACegQIIhAB&url=http%3A%2F%2Fwww.cs.toronto.edu%2F~dt%2Fsiggraph97-course%2Fcwr87%2F&usg=AOvVaw2StOMrXs0E_nHLgD87UrGN). [Here’s a video of the original simulation in action](https://www.youtube.com/watch?v=86iQiV3-3IA). For an in-depth treatment of agent-based steering algorithms more generally (including Boids) try [this chapter from the Nature of Code](https://natureofcode.com/book/chapter-6-autonomous-agents/).  The author of this chapter also walks through implementing the algorithm in [his amazing Coding Train series](https://www.youtube.com/watch?v=mhjuuHl6qHM). But the first link in this assignment is perhaps the easiest to follow, with clear pseudocode and explanations of the algorithm. 

In some ways, this simulation is simpler than our previous Physarum simulation, as we don't have an underlying continuous layer to deal with (unless you want to add one that influences the agents in some way). But our complexity now becomes that boids need to know about each other in a way we haven't explored before. In the game of life, cells needed to know about their immediate neighbors; here every agent needs to (potentially) know about every other agent in the flock.

This means we need a way to loop through the flock. It would be fantastic if there was a simple way to loop through all vertices in a vertex buffer object (like what we used to represent our agents in the physarum simulation) but that way doesn't exist. 

So, an alternative: we use transform feedback to move our agents and have them respond to each other. We then render each agent's position and velocity to one pixel of a RGBA texture. In each tick of our simulation, we can loop through this texture one pixel at a time (you can use `texelFetch()` to look in a texture by pixel instead of using normalized coordinates) and respond to each agent.

Remember that if, for every given agent A, we're looking up all other agents stored in group A\* of size 8192, that means processing all agents will require 8192*8192 texture lookups... 67 million! And that's not even including all the actual vector math that is performed once we have the position of each agent. That said, on even a moderately new integrated graphics card you can expect a 15-20x speedup by running boids on the GPU instead of the CPU. For fancy graphics cards (1080, 2080, 3060 on up) you can expect even more than this. It's worth the effort!

OK, here we go!

## The Setup

The [template project we'll use for this tutorial](https://github.com/imgd-cs-420x-2022/boids.start) is going to require `parcel` for building. This will enable us to place our GLSL in separate files and help us organize a bit. The template also includes some simple helper functions for making shaders, buffers, and textures. 

All of our JavaScript will be in the `main.js` file, which is then loaded in a `<script>` tag in `index.html`. Here's the start of our `main.js` file:

```js
import simulation_frag from './simulation.frag.glsl'
import simulation_vert from './simulation.vert.glsl'
import render_frag from './render.frag.glsl'
import render_vert from './render.vert.glsl'

// "global" variables
let gl, 
    buffers

const textures = [] 

window.onload = function() {
  const canvas = document.getElementById( 'gl' )
  gl = canvas.getContext( 'webgl2' )
  canvas.width  = window.innerWidth
  canvas.height = window.innerHeight

  render()
}
```

OK, so we start of with a few import commands to load our shaders into strings. Parcel will handle the details of this for us, great! We have a few global variables, and then our `window.onload` function, which basically grabs a webgl2 context and sets the width and height of it.

Let's add a bit to this. We're going to structure our simulation in a similar to what we did with Physarum, where each shader and call to `gl.drawXYZ()` will be setup in its own function. We'll also add a bunch of global variables that we'll need throughout the program.

```js
import simulation_frag from './simulation.frag.glsl'
import simulation_vert from './simulation.vert.glsl'
import render_frag from './render.frag.glsl'
import render_vert from './render.vert.glsl'

// "global" variables
let gl, 
    transformFeedback, 
    framebuffer,
    simulationProgram, simulationPosition, 
    renderProgram, 
    buffers

const textures = [], 
      agentCount = 8192

window.onload = function() {
  const canvas = document.getElementById( 'gl' )
  gl = canvas.getContext( 'webgl2' )
  canvas.width  = window.innerWidth
  canvas.height = window.innerHeight

  makeSimulationPhase()
  makeRenderPhase()
  makeTextures()

  framebuffer = gl.createFramebuffer()

  render()
}
```

So we can see here that there will be two render phases. In the simulation, each of our agents--each presented by a single vec4 associated with on vertex--will react to the position of other agents, changing its position and velocity; this all happens in the vertex shader and is saved into a vertex buffer object via transform feedback. In the fragment shader we will then render the state of each agent to a single pixel inside a texture. This is the texture we'll use in subsequent calls to the vertex shader so we can lookup information about individual agents.

In the render phase, we'll take the output of the transform feedback and simply render it to the screen using `gl.POINTS`. The render phase is extremely simple (less than 20 lines of GLSL for both the vertex and fragment shader combined)... most of the work is happening in the vertex simulation shader.

## A couple of convenience functions

Here's a couple of convenience functions I wrote. The first lets you pass in text from a vertex shader and a fragment shader and outputs a shader program; it also accepts an optional argument of vertex attributes to feed into transform feedback. The second generates vertex buffer objects. If you ask for a single object (the default) it will create that object and return it. If you ask for multiple buffers it will return an array populated with the requested buffers.

```js
function makeProgram( vert, frag, transform=null ) {
  let vertexShader = gl.createShader( gl.VERTEX_SHADER )
  gl.shaderSource( vertexShader, vert )
  gl.compileShader( vertexShader )
  let err = gl.getShaderInfoLog( vertexShader )
  if( err !== '' ) console.log( err )

  const fragmentShader = gl.createShader( gl.FRAGMENT_SHADER )
  gl.shaderSource( fragmentShader, frag )
  gl.compileShader( fragmentShader )
  err = gl.getShaderInfoLog( fragmentShader )
  if( err !== '' ) console.log( err )

  const program = gl.createProgram()
  gl.attachShader( program, vertexShader )
  gl.attachShader( program, fragmentShader )

  // transform feedback must happen before shader is linked / used.
  let trasformFeedback
  if( transform !== null ) {
    transformFeedback = gl.createTransformFeedback()
    gl.bindTransformFeedback(gl.TRANSFORM_FEEDBACK, transformFeedback)
    gl.transformFeedbackVaryings( program, transform, gl.SEPARATE_ATTRIBS )
  }
  
  gl.linkProgram( program )

  // return an array containing shader program and transform feedback
  // if feedback is enabled, otherwise just return shader program
  return transform === null ? program : [ program, transformFeedback ]
}

function makeBuffers( array, count=1, usage=gl.STATIC_DRAW ) {
  const buffer = gl.createBuffer()
  gl.bindBuffer( gl.ARRAY_BUFFER, buffer )
  gl.bufferData( gl.ARRAY_BUFFER, array, usage )

  let buffers = null
  if( count > 1) {
    buffers = [ buffer ]
    for( let i = 0; i < count; i++ ) {
      const buff = gl.createBuffer()
      gl.bindBuffer( gl.ARRAY_BUFFER, buff )
      gl.bufferData( gl.ARRAY_BUFFER, array.byteLength, usage )
      
      buffers.push( buff )
    }
  }

  return Array.isArray( buffers ) ? buffers : buffer
}
```

## Simulation Phase (part 1)
OK, here we go. If you've read the rules of the boids algorithm you know that one of them is cohesion, where the boids move towards each other by some given amount. This is the one (and only) rule we'll move towards implementing here... but many of the other rules use a similar process.

Our goal, again, is to take a vertex buffer and render its contents into a texture, so that we can use the texture to know where all the agents are in the scene. We can use some tricks to simplify this... the first is that we'll use a texture with some *ahem* interesting dimensions. Given a flock of length `N`, our texture will be `N` pixels in width and `1` pixel in height. This basically turns the texture into a one dimensional array that we can easily loop through with a single for loop. The math to exactly place a given vertex into its slot in this array is pretty simple, as we'll see momentarily. 

Here's the contents of `simulation.vert.glsl`:

```glsl
#version 300 es
precision mediump float;

// last reported agent (vertex) position/velocity
in vec4 agent_in;

// texture containing position/velocity of all agents
uniform sampler2D flock;
// total size of flock 
uniform float agentCount;

// newly calculated position / velocity of agent
out vec4 agent_out;

void main() {
  // the position of this vertex needs to be reported
  // in the range {-1,1}. We can use the gl_VertexID
  // input variable to determine the current vertex's
  // position in the array and convert it to the desired range.
  float idx = -1. + (float( gl_VertexID ) / agentCount) * 2.; 

  // we'll use agent_out to send the agent position and velocity
  // to the fragment shader, which will render it to our 1D texture.
  // agent_out is also the target of our transform feedback.
  agent_out = agent_in;
  
  // loop through all agents...
  for( int i = 0; i < int( agentCount ); i++ ) {
    // make sure the index isn't the index of our current agent
    if( i == gl_VertexID ) continue;
    
    // get our agent for comparison. texelFetch accepts an integer
    // vector measured in pixels to determine the location of the
    // texture lookup. 
    vec4 agent  = texelFetch( flock, ivec2(i,0), 0 );

    // move our agent a small amount towards the ith agent
    // in the flock.
    agent_out.xy += ( agent_out.xy - agent.xy) * -.02 / agentCount;
  }
  
  // each agent is one pixel. remember, this shader is not used for
  // rendering to the screen, only to our 1D texture array.
  gl_PointSize = 1.;

  // report our index as the x member of gl_Position. y is always 0.
  gl_Position = vec4( idx, .0, 0., 1. );
}
```

OK, so now our vertex shader has transformed the position of our agent (we're not currently using velocity, but you could easily store that in the `.zw` members) and exported them to the fragment shader via `agent_out`; this is also being passed to our transform feedback so the new position will be found in `agent_in` in our next simulation tick. We assign the index of the current vertex, normalized to a {-1,1} range, to the `gl_Position` output variable. After binding the appropriate 1D texture to our shader program / draw call, our fragment shader will render to that 1D texture array in the correct position.

Our fragment shader is much simpler... we simply write the contents of `agent_out`.

```glsl
#version 300 es
precision mediump float;

in  vec4 agent_out;
out vec4 frag;

void main() {
  frag = agent_out;
}
```

OK, now that we have our simulation glsl, let's write the JavaScript needed to compile / link the shader and setup the necessary uniforms and attributes.

### Simulation Phase: JavaScript
In our `window.onload` function there's a call to `makeSimulationPhase()`. Here's that function:

```js
function makeSimulationPhase(){
  // pass in our vertex/fragment shader source code, and specify
  // that the attribute agent_out should be fed into transform feedback
  const shader = makeProgram( simulation_vert, simulation_frag, ['agent_out'])
  simulationProgram = shader[0]
  transformFeedback = shader[1]

  gl.useProgram( simulationProgram )

  buffers = makeSimulationBuffer()

  makeSimulationUniforms()
}
```

Not to much to point out here. Let's look at the `makeSimulationBuffer` and `makeSimulationUniforms` functions:

```js
function makeSimulationBuffer() {
  const __agents = []
  for( let i = 0; i <= agentCount * 4; i+=4 ) {
    __agents[i] = -1 + Math.random() * 2
    __agents[i+1] = -1 + Math.random() * 2
    // use i+2 and i+3 to set initial velocities, default to 0
  }
  const agents = new Float32Array( __agents ) 

  // makeBuffers accepts initial data, number of buffers, and buffer usage
  // we'll make two buffers so we can complete the necessary swaps for
  // transform feedback
  return makeBuffers( agents, 2, gl.DYNAMIC_COPY )
}

function makeSimulationUniforms() {
  // this input variable will be fed by feedback
  const simulationPosition = gl.getAttribLocation( simulationProgram, 'agent_in' )
  gl.enableVertexAttribArray( simulationPosition )
  gl.vertexAttribPointer( simulationPosition, 4, gl.FLOAT, false, 0,0 )

  // number of agents in our flock
  const count  = gl.getUniformLocation( simulationProgram, 'agentCount' )
  gl.uniform1f( count, agentCount )
}
```

## Render Phase

The render phase is easy. We take the vertex buffer output of our transform feedback, and bind it to our render shader... this gives us the position and velocity of each agent feeding our vertex shader, We assign this position to `gl_Position` in the vertex shader, while our fragment shader simply colors the point sprite representing the agent; we'll turn on blending in our `makeRenderPhase()` function. 

render.vert.glsl:  
```glsl
#version 300 es
in vec4 agent;

void main() {
  gl_PointSize = 20.;
  gl_Position = vec4( agent.xy, 0., 1. );
}

```

render.frag.glsl:  
```glsl
#version 300 es
#ifdef GL_ES
precision mediump float;
#endif

out vec4 color;
void main() {
  color = vec4( 1.,0.,1., .1 );
}
```

```js
function makeRenderPhase() {
  renderProgram  = makeProgram( render_vert, render_frag )
  const renderPosition = gl.getAttribLocation( renderProgram, 'agent' )
  gl.enableVertexAttribArray( renderPosition )
  gl.vertexAttribPointer( renderPosition, 4, gl.FLOAT, false, 0,0 )

  gl.useProgram( renderProgram )
  gl.enable(gl.BLEND)
  gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA)
}
```

## Textures
OK, let's throw in our `makeTextures()` function. This code doesn't look any different from the textures made in previous tutorials, EXCEPT that they are only *one pixel in height* and we're using floating point textures.

```js
function makeTextures() {
  textures[0] = gl.createTexture()
  gl.bindTexture( gl.TEXTURE_2D, textures[0] )
  gl.getExtension('EXT_color_buffer_float');
  
  gl.texParameteri( gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE )
  gl.texParameteri( gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE )
  gl.texParameteri( gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST )
  gl.texParameteri( gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST )
  // width = agentCount, height = 1
  gl.texImage2D( gl.TEXTURE_2D, 0, gl.RGBA32F, agentCount, 1, 0, gl.RGBA, gl.FLOAT, null )

  textures[1] = gl.createTexture()
  gl.bindTexture( gl.TEXTURE_2D, textures[1] )
  gl.texParameteri( gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE )
  gl.texParameteri( gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE )
  gl.texParameteri( gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST )
  gl.texParameteri( gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST )
  gl.texImage2D( gl.TEXTURE_2D, 0, gl.RGBA32F, agentCount, 1, 0, gl.RGBA, gl.FLOAT, null )
}
```

## Render
Last but not least, our render function!

```js
function render() {
  window.requestAnimationFrame( render )

  gl.useProgram( simulationProgram )

  gl.bindFramebuffer( gl.FRAMEBUFFER, framebuffer )
  
  // specify rendering to a width equal to the number of agents,
  // but only one high for simplicity of lookup
  gl.viewport( 0,0,agentCount, 1 )
  
  // render to textures[1], swap at end of render() 
  gl.framebufferTexture2D( gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, textures[1], 0 )
  
  // read from textures[0], swap at end of render()
  gl.activeTexture( gl.TEXTURE0 )
  gl.bindTexture(   gl.TEXTURE_2D, textures[0] )

  // feedback transform
  gl.bindBuffer( gl.ARRAY_BUFFER, buffers[0] )
  gl.vertexAttribPointer( simulationPosition, 4, gl.FLOAT, false, 0,0 )
  gl.bindBufferBase( gl.TRANSFORM_FEEDBACK_BUFFER, 0, buffers[1] )
  
  gl.beginTransformFeedback( gl.POINTS )  
  // draw via POINTS
  gl.drawArrays( gl.POINTS, 0, agentCount )
  gl.endTransformFeedback()

  gl.bindBufferBase( gl.TRANSFORM_FEEDBACK_BUFFER, 0, null )

  gl.bindFramebuffer( gl.FRAMEBUFFER, null )

  // important!!! last render was specified as only one pixel in height,
  // that won't do for rendering our quad
  gl.viewport( 0,0, gl.drawingBufferWidth, gl.drawingBufferHeight )

  gl.useProgram( renderProgram )
  gl.bindBuffer( gl.ARRAY_BUFFER, buffers[0] )
  gl.drawArrays( gl.POINTS, 0, agentCount )

  // swaps
  let tmp = buffers[0];  buffers[0] = buffers[1];  buffers[1] = tmp;
  tmp = textures[0]; textures[0] = textures[1]; textures[1] = tmp;
}
```

... and that does it!!!   
