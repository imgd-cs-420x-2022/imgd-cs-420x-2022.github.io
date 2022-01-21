void main() {
  vec2 p = uv();
  float color = 0.; 
  float frequency = 2.;
  float gain = 1.;
  float thickness = .025;
  
  p.x = abs(p.x);
  p.y = abs(p.y);
  
  p = rotate(p, vec2(0, 0), time*0.2);
  
  p.x = mod(p.x - time/10000., -1.-0.4*sin(time));
  p.y += mod(p.y - time/1000., 1.+1.5*cos(time));

  for( float i = 0.; i < 4.; i++ ) { 
    p.x += sin(p.y + time * i) * gain;
    
    p.yx = rotate(p, vec2(0, 0), time*0.1).xy;
    
    color += abs( sin(0.5*time)/5.*thickness / p.y + sin(time*0.5)/2.*thickness / p.x);
  }
  
  vec4 lastFrame = texture2D(backbuffer, rotate(p, vec2(0, 0), time*2.));
  
  float feedback = color + lastFrame.z * 0.5;
  float fbBlue = sin(feedback) - lastFrame.y * 0.75;
  
  float stime = 0.5*sin(time*0.3)+0.5;
  float ctime = 0.5*cos(time*0.3)+0.5;
  
  float red = mix(fbBlue, feedback, stime);
  float blue = mix(fbBlue, feedback, ctime);
  
  vec4 c = vec4(red, blue, color, 1.);
  
  c.yz += noise(vec3(p, time*0.2))*0.1;

  gl_FragColor = vec4(c);
}
