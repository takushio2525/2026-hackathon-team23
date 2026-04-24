import ddf.minim.*;
import ddf.minim.ugens.*;

Minim minim;
AudioOutput out;

void setup()
{
	size(512, 200);
	// m i n i m のインスタンスを用意
	minim = new Minim(this);
	// m i n i m のg e t L i n e O u t メソッドを呼び出し， A u d i o O u t p u t オブジェクトを受け取る
	out = minim.getLineOut();
	// テンポの設定， BPM=120
	out.setTempo( 120 );
}

void playSong() {
	// 再生を停止
	out.pauseNotes();
	// 音を追加（ 開始時刻， 音の長さ， 音の高さ）---------- (a), (b)
	out.playNote(0.0f, 5.0, "A4");
	// 再生
	out.resumeNotes();
}

void draw()
{
	background(0);
	stroke(255);

	// 左チャンネルと右チャンネルに入っている波形を描画---------- (c)
	for (int i = 0; i < out.bufferSize() - 1; i++)
	{
		line( i, 50 - out.left.get(i)*50, i+1, 50 - out.left.get(i+1)*50 );
		line( i, 150 - out.right.get(i)*50, i+1, 150 - out.right.get(i+1)*50 );
	}
}

void keyPressed() {
	switch (key)
	{
		case 'p':
			// 作成した信号を出力
			playSong();
			break;
	}
}

