// Zeitgeber v0.0001

#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

// _COLOR_ vs _TEXTURE_ depends on whether we're using shader() or filter()
// (d.h., whether there's an underlying pixels[] to which we're applying the filter)
// With TEXTURE you get a builtin sampler called "texture"

#define PROCESSING_COLOR_SHADER
//#define PROCESSING_TEXTURE_SHADER

const float PI = 3.14159265359;

uniform vec2 resolution;

uniform float halfpulse; // in milliseconds
uniform float pulse;

uniform float time; // milliseconds since the start of the draw() loop
uniform float threshold; // pivot for calculating gain expression, e.g. contrast

// 5/2014: This may look like the Bad Way of doing things but--
// - Processing shader API does not support array binding
// - GLSL ES does not support looping over arrays (in GLSL < 4.0 array indices are const)
//   http://stackoverflow.com/questions/12030711/glsl-array-of-textures-of-differing-size/

// TODO: Add halfpulse, pulse, skew and threshold for all of these

uniform sampler2D stream0;
uniform sampler2D stream1;
uniform sampler2D stream2;

uniform float period0; // in ms
uniform float period1;
uniform float period2;

uniform float phase0; // in ms
uniform float phase1;
uniform float phase2;

uniform float gain0; // 1-based, i.e. a coefficient
uniform float gain1;
uniform float gain2;

uniform vec3 balance0; // RGB for pulse expression
uniform vec3 balance1;
uniform vec3 balance2;

// TODO
// halfpulse0 1 2
// threshold0 1 2
// skew0 1 2
// flare0 1 2 (vec3)

// pulse phase in [0,1] -- 0 off-pulse, 1 at center of pulse
float pulsePhase( float period, float phase ) {
	return clamp( halfpulse - abs( mod( time, period + pulse ) - phase ), 0., halfpulse ) / halfpulse;
		// + pulse to handle edge-of-period half-pulse problem
}

// Easing to simulate Fourier modeling of pulse shape
// - Start with pulse phase in [0,1]
// - Map it to [ sin(-π/2), sin(π/2) ], map that back to [0,1]
// - Map that to [ 1., gain ]
float easing( float phase, float gain ) {
	float pulse = .5 + .5 * sin( PI * ( phase - .5 ) );
	return pulse * ( gain - 1. ) + 1.;
}

// Right now, pulse expression is just an RGB-weighted contrast enhancement,
// eased according to where in the time course of the pulse we are (pulsePhase)
// TODO -- Add a flare!
vec3 pulse( vec3 c, float pulsePhase, float gain, float threshold, vec3 balance ) {
	return balance.rgb * ( ( c.rgb - threshold ) * easing( pulsePhase, gain ) + threshold );
		// Achtung, color balance here is a MULTIPLIER, not an apportioner
}

void main() {
	// We could use vertTexCoord and texOffset (Processing uniforms),
	// but it feels more portable to roll our own

	// Invert y-axis -- Processing y-axis runs top to bottom
	vec2 pos = vec2( gl_FragCoord.s / resolution.s, 1. - (gl_FragCoord.t / resolution.t) );

	// 1-texel offset for convolution filtering
	vec2 off = vec2( 1. / resolution.s, 1. / resolution.t );

	// Sample texture data for current fragment
	vec4 c0 = texture2D( stream0, pos );
	vec4 c1 = texture2D( stream1, pos );
	vec4 c2 = texture2D( stream2, pos );

	//
	// For each stream, do something special if its oscillator is on-pulse
	// Right now the something special is just heightened contrast

	// Inspired by http://glsl.heroku.com/e#15220.0

	float pulsePhase0 = pulsePhase( period0, phase0 );
	float pulsePhase1 = pulsePhase( period1, phase1 );
	float pulsePhase2 = pulsePhase( period2, phase2 );

	// TODO --
	// Add a flare, drawing in the color values from neighboring texels
	// Look at http://glsl.heroku.com/e#15220.0 --
	// Maybe use an exponential distance decay from current position

	// TODO --
	// Make pulsePhase ± so we can add some asymmetry to the easing -- sharper attack, longer decay etc
	// Maybe have it vary [0,2], with >1 postpeak ...
	// or use a vec2 with sign represented separately

	if ( pulsePhase0 > 0. ) {
		c0.rgb = pulse( c0.rgb, pulsePhase0, gain0, threshold, balance0 );
	}
	if ( pulsePhase1 > 0. ) {
		c1.rgb = pulse( c1.rgb, pulsePhase1, gain1, threshold, balance1 );
	}
	if ( pulsePhase2 > 0. ) {
		c2.rgb = pulse( c2.rgb, pulsePhase2, gain2, threshold, balance2 );
	}

	// TODO: Rethink
	// Blend the textures
	// We use a lighten blend, not a linear tween
	// The video streams are characterized by dark backgrounds with bright shapes
	// So a tween would mute the colors
	vec4 blend = max( c0, max( c1, c2 ) );

	gl_FragColor = vec4( blend.rgb, 1. ) ; //* vertColor;
}



	// TODO -- Motion blur! Use offsets at multiple steps from the current fragment for bigger blur
	// http://lodev.org/cgtutor/filtering.html
	// Modularize with arrays -- radius-2 texel matrix == [25], rad-2 convolution matrix, pass those in w offset, get out convolved color
	// Or for efficiency just [5] for the row, if we're doing transverse motion blur
	// -- and the gain is represented by blur radius and duration ...

