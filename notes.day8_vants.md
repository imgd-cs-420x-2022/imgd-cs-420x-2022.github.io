# Langton’s Ants (vants)
OK,  it’s time to bring a bunch of different elements together to realize our our next simulation, Langton’s Ants (aka virtual ants aka vants). But before we dive into the code, let’s take a moment to watch this excellent video that both explains the underlying algorithm and features a great score write by Steina and Woody Vasulka, who, when they weren’t composing, were also pioneers of experimental video art. It might be the only SIGGRAPH video you ever see with a custom score written by famous folks:

https://www.youtube.com/watch?v=w6XQQhCgq5c

This will be our most complex simulation yet in terms of the WebGL required to render it, BUT, the shaders are (thankfully) fairly simple. In the video Langton implements two different types of vants, here we’ll just implement one, leaving you room to experiment. Because the WebGL is fairly complex, we’ll be careful to organize/break up our code to make it easier to read / navigate / reason about.

## Bringing vants to WebGL: an overview
First of all, I’ll point out it is actually possible to run a fragment-shader-only version of Langton’s Ants, where every pixel is a vant:

https://www.shadertoy.com/view/WtS3zy

While (really really really) cool as a technical demo, the above example is perhaps limited in some ways… although definitely not in terms of vant population! But what if we only wanted a few vants? In order to realize a more flexible approach, we’ll combine vertex shaders (where every vertex will represent a vant moved around via transform feedback) with fragment shaders (the fragment shaders will keep track of the “pheromones” ants leave aka trails). 

The core algorithm of our vant:

1. “Sniff” its current location to detect the presence of pheromones
2. *Pheremones found*: Turn 90 degrees counter clockwise, and remove pheromones.
3. *Pheremones not found*: Turn 90 degrees clockwise and leave pheromones.

That’s it. To do this technically we’ll need:

1. “Sniff”: sample a texture which will hold our pheromones traiil
2. *Pheremones found* and *Pheromones not found*: adjust the heading of our vant… since we’re only turning 90 degrees at a time there are only four possible headings, which will prove useful for representation. Update the texture holding the pheromone trail

We’ll use a single vertex with one `vec4` attribute to represent each vant. It will hold:

```js
[
  x_position,
  y_position,
  heading,
  sniff_result
] 
```

We’ll use the sniff result to adjust our pheromone trail texture; each vertex will be drawn via `gl.POINTS` (see the notes from last class if you need a refresher on vertex feedback transforms and `gl.POINTS`)

Our representation will just be our pheromone trail. We’ll use black to represent no pheromones / never have been, red to say active pheromones, and blue to show “depleted” pheromones.

OK!!! Let’s code this up.

## WebGL setup
For convenience, we’ll do this in a single HTML file, but it’s pushing the limits of readability. If you’re comfortable using Parcel you might want to use that to break up the GLSL into separate files and import them.

Our beginning HTML template will look like this:

```html
<!doctype html>
<html lang='en'>
  <head>
    <style>body{ margin:0; background: black; }</style>
  </head>
  <body>
    <canvas id='gl'></canvas>
  </body>

  <script id='copyVertex' type='x-shader/x-vertex'></script>
  <script id='copyFragment' type='x-shader/x-fragment'></script>
  <script id='simulationVertex' type='x-shader/x-vertex'></script>
  <script id='simulationFragment' type='x-shader/x-fragment'></script>

  <script type=‘text/javascript’>
    window.onload = function() {
    
    }
  </script>

</html>
```

OK, so as you can see we’ll have two different shader programs. The first is our “copy” shader… this will just sample from our texture holding the pheromone trail and display it on the screen. In a new twist for this course, we’ll also be using this shader to copy between textures.

The second shader program will be our simulation shader. This will feature a vertex shader that will do most of the heavy lifting… the fragment shader will just color the current vant according to whether or not it detected any pheromones at its location.

## Creating some “global” variables and defining our window.onload callback
Here’s our variable setup and our entire `window.onload` function. Note we’ve divided most of the functionality among different functions, making onload a bit easier to read. Paste this inside of the final `<script>` tag:

```js
    let gl, uTime, uRes, transformFeedback, 
        buffer1, buffer2, simulationPosition, copyPosition,
        textureBack, textureFront, framebuffer,
        copyProgram, simulationProgram, quadBuffer,
        dimensions = { width:null, height:null },
        antCount = 1

    window.onload = function() {
      const canvas = document.getElementById( 'gl' )
      gl = canvas.getContext( 'webgl2' )
      const dim = window.innerWidth < window.innerHeight ? window.innerWidth : window.innerHeight
      canvas.width  = dimensions.width  = dim
      canvas.height = dimensions.height = dim 

      // define drawing area of canvas. bottom corner, width / height
      gl.viewport( 0,0,gl.drawingBufferWidth, gl.drawingBufferHeight )

      makeCopyPhase()
      makeSimulationPhase()
      makeTextures()
      render()
    }

```

A couple of important points:
1. We want a square grid. We’ll get this by looking at the smallest dimension, and then setting the other dimension of our canvas to match.
2. We have a lot of globals! There’s a bunch of data we need to share between our different functions. You could wrap these up in an object or take some other approach if you like.
3. We’re using WebGL 2
4. Pay special attention to the `antCount` variable! This will be used in a few different parts of our code, and, as you might expect, controls the number of vants in the simulation.

## `makeCopyPhase()`
Our model will actually consist of three parts. First, we’ll run the simulation. Next, we’ll copy the results from one texture into another, so that they’re identical after the simulation runs. Then, we’ll copy our texture to the default framebuffer so it’s drawn on screen. Let’s take care of the copy shader / javascript first, as it’s a bit simpler.

```js
function makeCopyPhase() {
  makeCopyShaders()
  quad = makeCopyBuffer()
  makeCopyUniforms()
}
```

 OK, so creating our copy phase will consist of three steps. First, we’ll compile / link our shaders. Next, we’ll create the two triangles that combine to form our full-screen quad. Finally, we’ll generate all uniforms that we need (which will be stored globally).

### `makeCopyShaders()`

Nothing fancy here… this should be fairly familiar from our game of life / reaction diffusion studies.
```js
    function makeCopyShaders() {
      let shaderScript = document.getElementById('copyVertex')
      let shaderSource = shaderScript.text
      let vertexShader = gl.createShader( gl.VERTEX_SHADER )
      gl.shaderSource( vertexShader, shaderSource )
      gl.compileShader( vertexShader )

      // create fragment shader
      shaderScript = document.getElementById('copyFragment')
      shaderSource = shaderScript.text
      const drawFragmentShader = gl.createShader( gl.FRAGMENT_SHADER )
      gl.shaderSource( drawFragmentShader, shaderSource )
      gl.compileShader( drawFragmentShader )
      console.log( gl.getShaderInfoLog(drawFragmentShader) )

      // create shader program  
      copyProgram = gl.createProgram()
      gl.attachShader( copyProgram, vertexShader )
      gl.attachShader( copyProgram, drawFragmentShader )
      
      gl.linkProgram( copyProgram )
      gl.useProgram( copyProgram )
    }
```

Before this can run we need to fill in the appropriate shaders. Inside of our `copyVertex` script tag place the following GLSL:

```glsl
#version 300 es
in vec2 a_pos;

void main() {
  gl_Position = vec4( a_pos, 0, 1 );
}
```

Our `copyFragment` shader is only a bit more complex:

```glsl
#version 300 es
#ifdef GL_ES
precision mediump float;
#endif

uniform sampler2D uSampler;
uniform vec2 resolution;

out vec4 color;
void main() {
  vec2 pos = gl_FragCoord.xy / resolution;
  vec4 tex = texture( uSampler, pos );
  color = vec4( tex.rgb, 1. );
}
```

Note in WebGL 2 we use the `texture()` function instead of `texture2D`. Otherwise this should look very similar from the previous “copy” shaders we’ve written.

That’s it for the copy shaders! Next we need to make the vertex buffer that will be used to render our quad.

### `makeCopyBuffer()`
This should also look familiar from past assignments. The biggest difference is that we’ll save a reference to our buffer, as we’ll need to explicitly bind to it every time we call our copy shader, as our simulation shader program will bind to a different buffer holding the vertices representing the vants. We’ll store the returned buffer inside the `quad` variable as part of our `makeCopyPhase` function.

```js
function makeCopyBuffer() {
  // create a buffer object to store vertices
  const buffer = gl.createBuffer()

  // point buffer at graphic context's ARRAY_BUFFER
  gl.bindBuffer( gl.ARRAY_BUFFER, buffer )

  const triangles = new Float32Array([
    -1, -1,
     1, -1,
    -1,  1,
    -1,  1,
     1, -1,
     1,  1
  ])

  // initialize memory for buffer and populate it. Give
  // open gl hint contents will not change dynamically.
  gl.bufferData( gl.ARRAY_BUFFER, triangles, gl.STATIC_DRAW )

  return buffer
}
```

### `makeCopyUniforms`

```js
function makeCopyUniforms() {
  uRes = gl.getUniformLocation( copyProgram, 'resolution' )
  gl.uniform2f( uRes, dimensions.width, dimensions.height )

  // get position attribute location in shader
  copyPosition = gl.getAttribLocation( copyProgram, 'a_pos' )
  // enable the attribute
  gl.enableVertexAttribArray( copyPosition )
  // this will point to the vertices in the last bound array buffer.
  // In this example, we only use one array buffer, where we're storing 
  // our vertices. Each vertex will have to floats (one for x, one for y)
  gl.vertexAttribPointer( copyPosition, 2, gl.FLOAT, false, 0,0 )
    }
```

## `makeSimulationPhase()`
OK, our copy phase is all setup, we’ll call it later when we define our final `render()` function. Next is the simulation phase, which will be a little bit trickier… but not too bad! We have a high-level function to setup our simulation, basically the same sequence that we did our copy phase in:

```js
function makeSimulationPhase(){
  makeSimulationShaders()
  makeSimulationBuffer()
  makeSimulationUniforms()
}
```

### `makeSimulationShaders()`
This really is almost identical to our `makeCopyShaders` function, with the exception that we’re throwing in transform feedback. You could probably refactor this to make one `setupShader` function if you want to avoid repeating yourself.

```js
function makeSimulationShaders() {
      let shaderScript = document.getElementById('simulationVertex')
      let shaderSource = shaderScript.text
      let vertexShader = gl.createShader( gl.VERTEX_SHADER )
      gl.shaderSource( vertexShader, shaderSource )
      gl.compileShader( vertexShader )

      // create fragment shader
      shaderScript = document.getElementById('simulationFragment')
      shaderSource = shaderScript.text
      const simulationFragmentShader = gl.createShader( gl.FRAGMENT_SHADER )
      gl.shaderSource( simulationFragmentShader, shaderSource )
      gl.compileShader( simulationFragmentShader )
      console.log( gl.getShaderInfoLog(simulationFragmentShader) )
      
      // create render program that draws to screen
      simulationProgram = gl.createProgram()
      gl.attachShader( simulationProgram, vertexShader )
      gl.attachShader( simulationProgram, simulationFragmentShader )

      transformFeedback = gl.createTransformFeedback()
      gl.bindTransformFeedback(gl.TRANSFORM_FEEDBACK, transformFeedback)
      gl.transformFeedbackVaryings( simulationProgram, ["o_vpos"], gl.SEPARATE_ATTRIBS )

      gl.linkProgram( simulationProgram )
      gl.useProgram(  simulationProgram )
    }
```

The transform feedback should be familiar from the particle effects tutorial we did last class… if not, make sure you go through that tutorial!

### `makeSimulationBuffer()`

We’re actually making two buffers here, as we need them to process the transform feedback. Remember,  you can’t read and write to the same buffer in on shader pass, the same way you can’t read and write to the same texture.

The big point of interest is the `Float32Array`; this is where we store the initial data for our vants. As we briefly mention before: [0] = x position (from -1 to 1), [1] = y position, [2] = heading, [3] = sniff results. For our headings, 0 will be to the right, 1 will be facing up, 2 will be facing left, and 3 will be facing down. The vant below should start in the center facing up.

```js
function makeSimulationBuffer() {
  // create a buffer object to store vertices
  buffer1 = gl.createBuffer()
  buffer2 = gl.createBuffer()

  // point buffer at graphic context's ARRAY_BUFFER
  gl.bindBuffer( gl.ARRAY_BUFFER, buffer1 )
  // we will be constantly updating this buffer data
  gl.bufferData( 
    gl.ARRAY_BUFFER, 
    new Float32Array(
      [
        0,0,1,0
      ]
    ), 
    gl.DYNAMIC_COPY 
  )

  gl.bindBuffer( gl.ARRAY_BUFFER, buffer2 )

	// antCount rears its head… remember to set this
  // to the number of vants you want!
  gl.bufferData( gl.ARRAY_BUFFER, antCount*16, gl.DYNAMIC_COPY )
}
```


### `makeSimulationUniforms()`

Nothing special to see here… 
```js
function makeSimulationUniforms() {
      uRes = gl.getUniformLocation( simulationProgram, 'resolution' )
      gl.uniform2f( uRes, gl.drawingBufferWidth, gl.drawingBufferHeight )
      
      // get position attribute location in shader
      simulationPosition = gl.getAttribLocation( simulationProgram, 'a_pos' )
      // enable the attribute
      gl.enableVertexAttribArray( simulationPosition )

		// remember, 4 floats per vant
      gl.vertexAttribPointer( simulationPosition, 4, gl.FLOAT, false, 0,0 )
    }
```

## Simulation phase shaders
OK, so the vertex shader for our simulation is where most of the work actually happens. Place this in the `simulationVertex` script tag. This script is a long one, make sure you read through all the comments to understand what’s happening here.

```glsl
#version 300 es
precision mediump float;

// input from our last frame via transform feedback
in vec4 a_pos;

// read the pheromone trail from here…
uniform sampler2D uSampler;

uniform vec2 resolution;

// our transform feedback outputs to this
out vec4 o_vpos;

// the four directions we’ll switch between.
// note the kinda weird constructor syntax for 
// glsl arrays…
vec2 dirs[4] = vec2[4](
  vec2(1.,0),
  vec2(0,1.),
  vec2(-1.,0),
  vec2(0,-1.)
);

void main() {
  // our vertex positions are reported from -1 to 1.
  // this converts that to 0 to 1, which is needed for
  // our texture lookup
  vec2 texCoord = 1. + a_pos.xy)/2.;
  float pheromone = texture( uSampler, texCoord ).r;

  // initialize our vertex transform output
  o_vpos = vec4( a_pos[0], a_pos[1], a_pos[2], pheromone);
	
	// how big is each square in the representation?
  float gridSize = 8.;
  
	// how far the vant should travel (but not the direction)
  float dist = (2. / resolution.x) * gridSize;

  // if pheromones were found
  if( pheromone > 0. ) {
    o_vpos[2] += 1.; // turn 90 degrees counter-clockwise
    o_vpos[3] = 1.;  // set pheromone flag
  }else{
    o_vpos[2] -= 1.; // turn clockwise
    o_vpos[3] = 0.;  // unset pheromone flag
  }
  
  // wrap direction lookup
  if( o_vpos[2] < 0. ) o_vpos[2] = 3.;
	
	// get direction from our array
  vec2 newdir = dirs[ int( mod( o_vpos[2], 4. ) ) ];
  
  gl_PointSize = gridSize;
	
	// set position for transform feedback
  o_vpos.xy += newdir * dist; 
  
	// send current position to fragment shader
  gl_Position = vec4( a_pos.x, a_pos.y, 0., 1. );
}
```

The fragment shader is *much* simpler. We just color the sprite based on whether or not pheromones were detected:

```glsl
#version 300 es
precision mediump float;

uniform vec2 resolution;

in  vec4 o_vpos;
out vec4 o_frag;

void main() {
  vec3 color = o_vpos[3] == 0. ? vec3(1.,0.,0.) : vec3(0.,0.,1.);
  o_frag = vec4( vec3( color ),1.);
} 
```

OK, all the shaders are now complete! All that’s left now is making some textures to hold our pheromone trail, and the final render function.

## `makeTextures()`
This should be similar from the game of life / reaction diffusion experiments. We’ll make two textures and a frame buffer.

```js
function makeTextures() {
  textureBack = gl.createTexture()
  gl.bindTexture( gl.TEXTURE_2D, textureBack )
  
  // these two lines are needed for non-power-of-2 textures
  gl.texParameteri( gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE )
  gl.texParameteri( gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE )
  
  // how to map when texture element is less than one pixel
  // use gl.NEAREST to avoid linear interpolation
  gl.texParameteri( gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST )
  // how to map when texture element is more than one pixel
  gl.texParameteri( gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
  
  // specify texture format, see https://developer.mozilla.org/en-US/docs/Web/API/WebGLRenderingContext/texImage2D
  gl.texImage2D( gl.TEXTURE_2D, 0, gl.RGBA, dimensions.width, dimensions.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null )

  textureFront = gl.createTexture()
  gl.bindTexture( gl.TEXTURE_2D, textureFront )
  gl.texParameteri( gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE )
  gl.texParameteri( gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE )
  gl.texParameteri( gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST )
  gl.texParameteri( gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST )
  gl.texImage2D( gl.TEXTURE_2D, 0, gl.RGBA, dimensions.width, dimensions.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null )

  // Create a framebuffer and attach the texture.
  framebuffer = gl.createFramebuffer()
}
```

## `render()`

OK, this ones a long one. Here’s the process:

1. Run our simulation using transform feedback on a vertex buffer where each vertex represents an ant.
2. Render each ant as a point sprite to a texture (offscreen frame buffer)
3. Our simulation needs to both *read* the pheromone trail, and *write* the pheromone trail. To do this we need two separate textures, however, unlike previous feedback examples, we don’t need to swap the texture references between frames. Instead, we just need to copy the freshly written texture to the designated “read” texture. We can do this using our copy shader.
4. Render everything to the screen using our copy shader (yes, we’re using it a second time in each render pass)
5. Swap our vertex buffers for the transform feedback to work correctly.

I’ve left comments below so that hopefully it all makes sense.

```js
function render() {
  window.requestAnimationFrame( render )
	
  // run the simulation first…
  gl.useProgram( simulationProgram )
  
  // ...and render to an offscreen frame buffer 
  gl.bindFramebuffer( gl.FRAMEBUFFER, framebuffer )

  // use the bound framebuffer to write to our textureFront texture
  gl.framebufferTexture2D( gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, textureFront, 0 )

  gl.activeTexture( gl.TEXTURE0 )
  // provide pheromone data to our shaders
  gl.bindTexture( gl.TEXTURE_2D, textureBack )

  // bind our array buffer of vants
  gl.bindBuffer( gl.ARRAY_BUFFER, buffer1 )
  // four floats per vant
  gl.vertexAttribPointer( simulationPosition, 4, gl.FLOAT, false, 0,0 )
  gl.bindBufferBase( gl.TRANSFORM_FEEDBACK_BUFFER, 0, buffer2 )
  
  gl.beginTransformFeedback( gl.POINTS )  
	// remember to set the antCount variable!!! And make sure
	// that you have four floats per vant in the Float32Array
  // created in the makeSimulationBuffer function
  gl.drawArrays( gl.POINTS, 0, antCount )
  gl.endTransformFeedback()

  /* COPY TEXTUREFRONT TO TEXTUREBACK */
	// use our currently bound frame buffer to write to
  // textureBack
  gl.framebufferTexture2D( gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, textureBack, 0 )

  // read from textureFront
  gl.activeTexture( gl.TEXTURE0 )
  gl.bindTexture(   gl.TEXTURE_2D, textureFront )
  
	// use our copy shader to do the copying
  gl.useProgram( copyProgram )

  // bind the vertices that make our full screen quad
  gl.bindBuffer( gl.ARRAY_BUFFER, quad )
  gl.vertexAttribPointer( copyPosition, 2, gl.FLOAT, false, 0,0 )

	// draw the full screen quad, completing the copy op
  gl.drawArrays( gl.TRIANGLES, 0, 6 )
  /* END COPY TEXTURE */

  /* COPY TO SCREEN */
  // use the default framebuffer object by passing null
  // this renders to screen
  gl.bindFramebuffer( gl.FRAMEBUFFER, null )
	
	// read from textureFront, although both textures
  // now contain the same pixels…
  gl.bindTexture( gl.TEXTURE_2D, textureFront )

  // use our drawing (copy) shader
  gl.useProgram( copyProgram )

  gl.bindBuffer( gl.ARRAY_BUFFER, quad )
  gl.vertexAttribPointer( copyPosition, 2, gl.FLOAT, false, 0,0 )

  // put simulation on screen
  gl.drawArrays( gl.TRIANGLES, 0, 6 )
  
  /* END COPY TO SCREEN */

  // because we copied texture A over to texture B we don't
  // need to do a texture swap, but we still need to swap
	// our vertex buffers  
  let tmp = buffer1;  buffer1 = buffer2;  buffer2 = tmp;
}
```

If all has gone well, you now have vants!!!
