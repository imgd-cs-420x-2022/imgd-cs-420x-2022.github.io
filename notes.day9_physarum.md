# Physarum (Slime Mold)
Today we’ll be looking at slime molds. Which are awesome. Really! Single-celled organisms with thousands / millions of nuclei.

- [Slime Mold Smarts](https://www.scientificamerican.com/article/brainless-slime-molds/)
- [Are you smarter than a slime mold?](https://www.youtube.com/watch?v=K8HEDqoTPgk)
- [Coding Adventure: Ant and Slime Simulations (thanks Eli!)](https://www.youtube.com/watch?v=X-iSQQgOd1A&t=9s)
- [Twitter feed for Sage Jenson](https://twitter.com/mxsage)

As it turns out, our model for Langton’s Ants gets us… most of the way to being able to do Physarum simulations. The core concept in Langton’s algorithm—agents move through a space leave trails of chemicals which in turn influence how agents move—is  the majority of what the Physarum simulation is all about. There’s a couple of other elements (of course):

1. Physarum nuclei have *sensors* they can use to detect chemical trails at locations that are distant from them
2. The chemical trails will both *diffuse* and *decay* over time. This requires a separate shader pass… to keep things simple, we’ll use the Laplace transform from the reaction diffusion model for diffusion; gaussian blurs are also recommended.
3. We’re going to use millions (!!!) of vertices to represent the nuclei of a slime mold. 

Here are a few different resources to learn more about the algorithm we’ll create:

- https://cargocollective.com/sagejenson/physarum
- https://jbaker.graphics/writings/physarum.html
- [Original paper on the simulation](http://eprints.uwe.ac.uk/15260/1/artl.2010.16.2.pdf)

I’ve placed a [completed simulation of Langton’s Ants](https://github.com/imgd-cs-420x-2022/imgd-cs-420x-2022.github.io/blob/main/langton_complete.html) based on the [tutorial from last class](https://github.com/imgd-cs-420x-2022/imgd-cs-420x-2022.github.io/blob/main/notes.day8_vants.md) in the course repo. We’re going to start from that simulation, and transform / extend it into slime mold.

### Good news!
We don’t need to change:

1. Anything about our copy shaders / buffers / uniforms
2. Anything about our WebGL setup for the vertex simulation shaders / buffers / uniforms (except the number of vertices used).
3. Anything about our render texture setup
4. Very little about our render function… we’ll bring back the texture swap that we took out in Langton’s, and instead of copying our simulation output from one texture to another we’ll run our decay / diffusion shader.

With that said, here are the things we have to change.

## Our simulation vertex shader
This is where the bulk of the work happens. The algorithm for the vertex shader is as follows for each agent:

1. “Look” or “sense” ahead, to the left, and to the right, to see where the greatest concentration of chemicals is. If left and right values are equal, randomly pick one.
2. Rotate the agent’s heading towards the greatest concentration of chemicals
3. Move agent one pixel along the new heading

Pretty simple algorithm, but it takes (well, it takes me, at least) about sixty lines of code implement. We’ll create a couple of utility functions in addition to our main program. The first will accept a 2D direction and rotate it a specified number of radians (not degrees!). The second will be used to “sense” chemical deposits at a given distance and direction away from the agent.

Our uniforms / varying will be the same from our Langton simulation.

```glsl
#version 300 es
#define PI_4 3.1415926538/4.
precision mediump float;

// input from our feedback TRANSFORM_FEEDBACK
in vec4 a_pos;

uniform vec2 resolution;

// our chemical layer
uniform sampler2D uSampler;

// the output of our feedback transform
// xy will store our position
// zw wiil store our heading / direction
out vec4 o_vpos;

// this function accepts a direction (header) for a
// agent and a rotation in radians, returning the
// new, rotated direction
vec2 rotate(vec2 dir, float angle) {
  float  s = sin( angle );
  float  c = cos( angle );
  mat2   m = mat2( c, -s, s, c );
  return m * dir;
}

// pos - position of agent
// dir - heading of agent
// angle - direction to sense, in radians
// distance - distance to sense
float readSensor( vec2 pos, vec2 dir, float angle, vec2 distance ) {
  vec2 newangle  = rotate( dir, angle  );
  vec2 offset = newangle * distance;
  return texture( uSampler, pos + offset ).r;
} 

void main() {
  // get normalied height / width of a single pixel 
  vec2 pixel = 1. / resolution;

  // how far ahead should sensing occur? this is fun to play with
  vec2 sensorDistance = pixel * 9.;

  // normalize our {-1,1} vertex coordinates to {0,1} for texture lookups
  vec2 pos = (1. + a_pos.xy) / 2.;

  // read sensor informatino at different angles
  float left     = readSensor( pos, a_pos.zw, -PI_4, sensorDistance );
  float forward  = readSensor( pos, a_pos.zw, 0.,    sensorDistance );
  float right    = readSensor( pos, a_pos.zw, PI_4,  sensorDistance );
  
  // initialize feedback transform output
  o_vpos = a_pos;

  // if most chemical is found to left... 
  if( left > forward && left > right ) {
    // rotate left and store in .zw
    o_vpos.zw = rotate( o_vpos.zw, -PI_4 );
  }else if( right > left && right > forward ) { // chemical is to the right
    o_vpos.zw = rotate( o_vpos.zw, PI_4 );
  }else if ( right == left ) { // randomly pick a direction
    float rand = fract(sin(a_pos.x)*100000.0);
    if( rand > .5 ) {
      o_vpos.zw = rotate( o_vpos.zw, PI_4 );
    }else{
      o_vpos.zw = rotate( o_vpos.zw, -PI_4 );
    }
  } // else keep going the same direction, no change required
  
  // move our agent in our new direction by one pixel
  o_vpos.xy += o_vpos.zw * pixel;
  
  gl_PointSize = 1.;

  // position is for fragment shader rendering, don't need to include heading
  gl_Position = vec4( a_pos.x, a_pos.y, 0., 1. );
}
```

Go ahead and test it as is… you should see one agent moving upwards at this point, with some possible randomization thrown in if you zoom in on it. That’s a start! Now… more agents.

## We need *lots* of agents
In our Langton example, we declare a variable named `antCount` at the top of our `window.onload` function. Let’s change it to `agentCount` and set it to a value of 1000. Also, jump to our `render` function and find the variable `antCount` and rename it to `agentCount` as well.   

Now we need to setup our simulation buffer to store these additional agents. Just like our Langton simulation, each agent will only have a single vec4 of information associated with it… this keeps things nice and simple. We’ll use a for loop to randomly initialize all of our heading and position data. While we’re here, we’ll also turn on blending.

```glsl
function makeSimulationBuffer() {
  // create a buffer object to store vertices
  buffer1 = gl.createBuffer()
  buffer2 = gl.createBuffer()

  // we’re using a vec4
  const agentSize = 4
  const buffer = new Float32Array( agentCount * agentSize )
	
	// set random positions / random headings
  for (let i = 0; i < agentCount * agentSize; i+= agentSize ) {
    buffer[i]   = -1 + Math.random() * 2
    buffer[i+1] = -1 + Math.random() * 2
    buffer[i+2] = Math.random()
    buffer[i+3] = Math.random()
  }

  gl.bindBuffer( gl.ARRAY_BUFFER, buffer1 )

  gl.bufferData( 
    gl.ARRAY_BUFFER, 
    buffer, 
    gl.DYNAMIC_COPY 
  )

  gl.bindBuffer( gl.ARRAY_BUFFER, buffer2 )

  gl.bufferData( gl.ARRAY_BUFFER, agentCount*16, gl.DYNAMIC_COPY )

  gl.enable(gl.BLEND);
  gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);
}
```

Test it out! You should see lots of agents moving around the screen, maybe they’re even making something interesting, but probably not quite yet. 

## Making it a bit prettier
Changing our render fragment shader to output transparent white might help aesthetics. Try `vec4( 1., 1., 1., .1 )` as a color. You can also get rid of the rest of the color changing code associated with the Langton simulation, so your render fragment shader should be as simple as:

```glsl
#version 300 es
precision mediump float;

out vec4 o_frag;
void main() {
  o_frag = vec4( 1., 1., 1., .1 );
} 
```

Test it out. Afterwards, update your agent count to a 10000 and see how it looks! You should see a clear network emerge. Next we need the chemicals the agents leave to both decay and diffuse over time. For that we’ll need another shader.

## Diffuse and Decay
As mentioned earlier, we’ll use our Laplace transform to diffuse the chemicals left by agents throughout our canvas. The decay will just be a simple scalar coefficient… the original paper on the simulation recommends starting with a value of .9, so we’ll do that. 

In this case we want the diffuse/decay shader to run on the fullscreen quad. We can use the `copyVertex` shader to cover the vertices for this, and then just make a script tag for the fragment shader. Add the following to your page:

```html
<script id='ddFragment' type='x-shader/x-fragment'>#version 300 es
#ifdef GL_ES
precision mediump float;
#endif  

uniform sampler2D uSampler;
uniform vec2 resolution;

float get(int x, int y) {
  return texture( uSampler, ( gl_FragCoord.xy + vec2(x, y) ) / resolution ).r;
}

out vec4 color;
void main() {
  float sum = get(0,0) - 1.;
  sum += get(-1,0)  *  .2;
  sum += get(-1,-1) *  .05;
  sum += get(0,-1)  *  .2;
  sum += get(1,-1)  *  .05;       
  sum += get(1,0)   *  .2;
  sum += get(1,1)   *  .05;
  sum += get(0,1)   *  .2;
  sum += get(-1,1)  *  .05;

  vec2 pos = gl_FragCoord.xy / resolution;
  vec4 tex = texture( uSampler, pos );
  color = vec4( vec3(sum * .9 ), .25 );
}
</script>
```

Hopefully that code for the Laplace looks familiar to you! Another common kernel to use here is a gaussian, where the coefficients are:

```
,0625  .125  .0625
.125   .25   .125
.0625  .125  .0625  
```

… try that out once we finish setting up our shader.

### Diffuse / Decay JavaScript
OK, now that we have our shader ready, let’s put it into our render pipeline. First we’ll add a call to `makeDecayDiffusePhase()` in our window.onload, similar to our other simulation phases. That function should look as follows:

```js
function makeDecayDiffusePhase() {
  makeDecayDiffuseShaders()
  makeDecayDiffuseUniforms()
}
```

We don’t need a function to make buffers, because we can just reuse the buffers from our copy phase, the same way we’re reusing its vertex shader. Basically, anytime you need to run a shader on a fullscreen quad you can reuse the copy phase vertex shader and associated vertex buffers.

There’s nothing special in `makeDecayDiffuseShaders`:

```js
function makeDecayDiffuseShaders() {
  let shaderScript = document.getElementById('copyVertex')
  let shaderSource = shaderScript.text
  let vertexShader = gl.createShader( gl.VERTEX_SHADER )
  gl.shaderSource( vertexShader, shaderSource )
  gl.compileShader( vertexShader )

  // create fragment shader
  shaderScript = document.getElementById('ddFragment')
  shaderSource = shaderScript.text
  const drawFragmentShader = gl.createShader( gl.FRAGMENT_SHADER )
  gl.shaderSource( drawFragmentShader, shaderSource )
  gl.compileShader( drawFragmentShader )
  console.log( gl.getShaderInfoLog(drawFragmentShader) )

  // create shader program  
  ddProgram = gl.createProgram()
  gl.attachShader( ddProgram, vertexShader )
  gl.attachShader( ddProgram, drawFragmentShader )
  
  gl.linkProgram( ddProgram )
  gl.useProgram( ddProgram )
}
```

Setting up the uniforms is simple as well:

```js
function makeDecayDiffuseUniforms() {
  uResDD = gl.getUniformLocation( ddProgram, 'resolution' )
  gl.uniform2f( uResDD, dimensions.width, dimensions.height )

  // get position attribute location in shader
  ddPosition = gl.getAttribLocation( ddProgram, 'a_pos' )
  // enable the attribute
  gl.enableVertexAttribArray( copyPosition )
  // this will point to the vertices in the last bound array buffer.
  // In this example, we only use one array buffer, where we're storing 
  // our vertices. Each vertex will have to floats (one for x, one for y)
  gl.vertexAttribPointer( copyPosition, 2, gl.FLOAT, false, 0,0 )
}
```

Make sure you add `ddProgram` and `ddPosition` as declared variables at the top of your `<script>` tag. Go ahead and test the file to make sure there’s no errors before we actually call the shader in our render function.

## Final render function
Not to big a difference here from our Langton simulation. The main difference is that we’ll bring back our texture swap, and then, instead of copying one texture to the other, we’ll run our diffuse / decay shader. Here’s how it looks:

```js
function render() {
  window.requestAnimationFrame( render )
	
	/* AGENT-BASED SIMULATION */
  gl.useProgram( simulationProgram )

  gl.bindFramebuffer( gl.FRAMEBUFFER, framebuffer )

  // use the framebuffer to write to our textureFront texture
  gl.framebufferTexture2D( gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, textureFront, 0 )

  gl.activeTexture( gl.TEXTURE0 )
  // read from textureBack in our shaders
  gl.bindTexture( gl.TEXTURE_2D, textureBack )

  // bind our array buffer of vants
  gl.bindBuffer( gl.ARRAY_BUFFER, buffer1 )
  gl.vertexAttribPointer( simulationPosition, 4, gl.FLOAT, false, 0,0 )
  gl.bindBufferBase( gl.TRANSFORM_FEEDBACK_BUFFER, 0, buffer2 )
  
  gl.beginTransformFeedback( gl.POINTS )  
  gl.drawArrays( gl.POINTS, 0, agentCount )
  gl.endTransformFeedback()
	/* END Agent-based simulation */

	/* SWAP */
  let _tmp = textureFront
  textureFront = textureBack
  textureBack = _tmp

  /* Decay / Diffuse */
  gl.framebufferTexture2D( gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, textureFront, 0 )

  gl.activeTexture( gl.TEXTURE0 )
  gl.bindTexture(   gl.TEXTURE_2D, textureBack )

  gl.useProgram( ddProgram )

  gl.bindBuffer( gl.ARRAY_BUFFER, quad )
  gl.vertexAttribPointer( ddPosition, 2, gl.FLOAT, false, 0,0 )

  gl.drawArrays( gl.TRIANGLES, 0, 6 )
  /* END Decay / Diffuse */

  /* COPY TO SCREEN */
  // use the default framebuffer object by passing null
  gl.bindFramebuffer( gl.FRAMEBUFFER, null )
  gl.viewport( 0,0,gl.drawingBufferWidth, gl.drawingBufferHeight )

  gl.bindTexture( gl.TEXTURE_2D, textureBack )

  // use our drawing (copy) shader
  gl.useProgram( copyProgram )

  gl.bindBuffer( gl.ARRAY_BUFFER, quad )
  gl.vertexAttribPointer( copyPosition, 2, gl.FLOAT, false, 0,0 )

  // put simulation on screen
  gl.drawArrays( gl.TRIANGLES, 0, 6 )
  /* END COPY TO SCREEN */

	// swap vertex buffers 
  let tmp = buffer1;  buffer1 = buffer2;  buffer2 = tmp;
}
```

Assuming that runs, up the agent count to a million and see how it goes!
