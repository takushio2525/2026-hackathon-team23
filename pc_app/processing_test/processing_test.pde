import ddf.minim.*;
import ddf.minim.ugens.*;

Minim minim;
AudioOutput out;
Waveform currentWaveform;

String[] melody = {
  "C4", "D4", "E4", "F4", "E4", "D4", "C4", //ドレミファミレド
  "E4", "F4", "G4", "A4", "G4", "F4", "E4", //ミファソラソファミ
  "C4", "C4", "C4", "C4",                   //ドドドド
  "C4", "C4", "D4", "D4", "E4", "E4", "F4", "F4", "E4", "D4", "C4"
                                            //ドドレレミミファファミレド
};

float[] duration = {
  0.75f, 0.75f, 0.75f, 0.75f, 0.75f, 0.75f, 1.5f,
  0.75f, 0.75f, 0.75f, 0.75f, 0.75f, 0.75f, 1.5f,
  0.75f, 0.75f, 0.75f, 0.75f,
  0.375f, 0.375f, 0.375f, 0.375f, 0.375f, 0.375f, 0.375f, 0.375f, 0.75f, 0.75f, 1.5f 
};

float[] startTime = {
  0.0f, 0.75f, 1.5f, 2.25f, 3.0f, 3.75f, 4.5f,
  6.0f, 6.75f, 7.5f, 8.25f, 9.0f, 9.75f, 10.5f,
  12.0f, 13.5f, 15.0f, 16.5f,
  18.0f, 18.375f, 18.75f, 19.125f, 19.5f, 19.875f, 20.25f, 20.625f, 21.0f, 21.75f, 22.5f
};

class HackInstrument implements Instrument
{
  Oscil wave;
  Line  ampEnv;
  float maxAmp;

  HackInstrument(float frequency, float maxAmp, Waveform wf )
  {
    wave = new Oscil(frequency, 0, wf);
    this.maxAmp = maxAmp;
    ampEnv = new Line();
    ampEnv.patch(wave.amplitude);
  }

  void noteOn( float duration )
  {
    ampEnv.activate(duration, this.maxAmp, 0);
    wave.patch( out );
  }

  void noteOff()
  {
    wave.unpatch( out );
  }
}

void setup()
{
  size(512, 200);
  minim = new Minim(this);
  out = minim.getLineOut();
  out.setTempo( 80 ); //BPM
  currentWaveform = Waves . SINE ;
}

void playSong() {
  out.pauseNotes();
  for (int i = 0; i < melody.length; i++) {
      out.playNote(startTime[i], duration[i],
        new HackInstrument(Frequency.ofPitch( melody[i] ).asHz(),
          0.5f, currentWaveform));
  }
  // 再生
  out.resumeNotes();
}

void draw()
{
  background(0);
  stroke(255);

  for (int i = 0; i < out.bufferSize() - 1; i++)
  {
    line( i, 50  - out.left.get(i)*50, i+1, 50  - out.left.get(i+1)*50 );
    line( i, 150 - out.right.get(i)*50, i+1, 150 - out.right.get(i+1)*50 );
  }
}

void keyPressed() {
  switch (key)
  {
    case 'p':
      playSong();
      break;
  }
}
