import processing.core.*; 
import processing.data.*; 
import processing.event.*; 
import processing.opengl.*; 

import processing.video.*; 

import java.util.HashMap; 
import java.util.ArrayList; 
import java.io.File; 
import java.io.BufferedReader; 
import java.io.PrintWriter; 
import java.io.InputStream; 
import java.io.OutputStream; 
import java.io.IOException; 

public class shadertest extends PApplet {

// Test of Processing shader API

// Result 0 (8.4.14): Can't pass an array to PShader::set()
// http://www.processing.org/reference/PShader_set_.html



final int SHADER_ID = 0;

final int N_LAYERS = 3;

PShader s;

Movie[] layers = new Movie[N_LAYERS];

public void setup() {
	size(720, 480, P2D);
	colorMode(RGB, 1.0f);

	s = loadShader("shaders/frag" + SHADER_ID + ".glsl");

	for (int i = 0; i < N_LAYERS; ++i) {
		layers[i] = new Movie(this, "movies/Doppelg\u00e4nger " + i + ".mov");
		layers[i].loop();
	}

	s.set( "frameDimensions", PApplet.parseFloat(width), PApplet.parseFloat(height) );	
}

public void draw() {
	background( color(0,0,0) );
	noStroke();

	for (int i = 0; i < N_LAYERS; ++i) {
		PImage frame = layers[i];
		s.set( "layer" + i, frame );
	}

	shader(s);
//	filter(s);
	rect(0, 0, width, height);
}

public void stop() {}

public void movieEvent(Movie m) {
	m.read();
}

  static public void main(String[] passedArgs) {
    String[] appletArgs = new String[] { "shadertest" };
    if (passedArgs != null) {
      PApplet.main(concat(appletArgs, passedArgs));
    } else {
      PApplet.main(appletArgs);
    }
  }
}
