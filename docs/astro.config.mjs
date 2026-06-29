// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// Astro Starlight は file:// ダブクリ閲覧をサポートしない。
// 閲覧は必ず `npm run dev` または `npm run preview` 経由で行う。
// GitHub Pages へデプロイする場合は site と base を以下のように設定:
//   site: 'https://takushio2525.github.io',
//   base: '/2026-hackathon-team23/',

export default defineConfig({
	integrations: [
		starlight({
			title: 'タクトーン',
			description: 'IMU ジェスチャーで奏でる Arduino オーケストラ — チーム 23 の設計・実装解説',
			customCss: ['./src/styles/paper-theme.css'],
			head: [
				{
					tag: 'script',
					content: `
window.MathJax = {
  tex: {
    inlineMath: [['\\\\(', '\\\\)'], ['$', '$']],
    displayMath: [['\\\\[', '\\\\]'], ['$$', '$$']],
    processEscapes: true,
  },
  svg: { fontCache: 'global' },
};

document.addEventListener('astro:page-load', () => {
  if (window.MathJax?.typesetPromise) {
    window.MathJax.typesetClear?.();
    window.MathJax.typesetPromise();
  }
});
`,
				},
				{
					tag: 'script',
					attrs: {
						id: 'MathJax-script',
						async: true,
						src: 'https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js',
					},
				},
				{
					tag: 'script',
					attrs: { type: 'module' },
					content: `
import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
mermaid.initialize({ startOnLoad: false, theme: 'neutral', securityLevel: 'loose' });

function extractCode(pre) {
  // expressive-code は各行を <div class="ec-line"><div class="code">...</div></div> に分割する。
  // textContent で取ると改行が失われるので、各行を \\n で連結する。
  const lines = pre.querySelectorAll('.ec-line');
  if (lines.length > 0) {
    return Array.from(lines).map((line) => {
      const code = line.querySelector('.code');
      return (code || line).textContent;
    }).join('\\n');
  }
  return pre.textContent;
}

function renderMermaid() {
  const blocks = document.querySelectorAll('pre[data-language="mermaid"]');
  blocks.forEach((pre) => {
    const code = extractCode(pre);
    const container = pre.closest('.expressive-code') || pre.closest('figure') || pre;
    const wrap = document.createElement('div');
    wrap.className = 'mermaid not-content';
    wrap.style.cssText = 'display:flex;justify-content:center;margin:1.5rem 0;overflow-x:auto;';
    wrap.textContent = code;
    container.replaceWith(wrap);
  });
  if (document.querySelectorAll('.mermaid').length > 0) {
    mermaid.run({ querySelector: '.mermaid' });
  }
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', renderMermaid);
} else {
  renderMermaid();
}
`,
				},
			],
			// social: [
			// 	{ icon: 'github', label: 'GitHub', href: 'https://github.com/takushio2525/2026-hackathon-team23' },
			// ],
			sidebar: [
				{
					label: 'はじめに',
					items: [
						{ label: 'ようこそ', slug: 'index' },
						{ label: 'プロジェクト概要', slug: 'intro/overview' },
						{ label: 'クイックスタート', slug: 'intro/quickstart' },
						{ label: '用語集', slug: 'intro/glossary' },
					],
				},
				{
					label: '現行システム',
					items: [
						{ label: 'システム全体', slug: 'system/overview' },
						{ label: '演奏体験と状態遷移', slug: 'system/experience' },
						{ label: 'ハードウェア構成', slug: 'system/hardware' },
						{ label: '通信プロトコル', slug: 'system/protocol' },
						{ label: '同期方式', slug: 'system/synchronization' },
						{ label: '楽譜と輪唱', slug: 'system/score' },
						{ label: 'ゲームモード', slug: 'system/game-mode' },
					],
				},
				{
					label: '開発ガイド',
					items: [
						{ label: '開発環境を準備する', slug: 'guide/setup' },
						{ label: 'リポジトリの使い方', slug: 'guide/repository' },
						{ label: 'ファームウェアを書き込む', slug: 'guide/firmware' },
						{ label: 'Processingを動かす', slug: 'guide/processing' },
						{ label: 'デバッグする', slug: 'guide/debug' },
						{ label: '評価・検証を行う', slug: 'guide/verification' },
						{ label: 'トラブルシュート', slug: 'guide/troubleshooting' },
						{ label: 'Gitで共同作業する', slug: 'guide/git' },
						{ label: 'LaTeX報告書', slug: 'guide/latex' },
					],
				},
				{
					label: '実装解説',
					items: [
						{ label: 'ファームウェア概要', slug: 'implementation/firmware-overview' },
						{ label: '共通モジュール', slug: 'implementation/common-modules' },
						{ label: '指揮者ノード', slug: 'implementation/conductor' },
						{ label: '楽器ノード', slug: 'implementation/instruments' },
						{ label: 'PCアプリ概要', slug: 'implementation/pc-overview' },
						{ label: 'PCのシリアル受信とUI', slug: 'implementation/pc-serial-ui' },
						{ label: '音声合成', slug: 'implementation/audio-synthesis' },
						{ label: '音色JSON', slug: 'implementation/instrument-json' },
						{ label: '拍検出アルゴリズム', slug: 'implementation/beat-detection' },
						{ label: '時刻同期アルゴリズム', slug: 'implementation/time-sync' },
						{ label: '楽譜進行アルゴリズム', slug: 'implementation/score-progression' },
						{ label: 'ナビゲーションと採点', slug: 'implementation/game-scoring' },
					],
				},
				{
					label: '音声解析',
					items: [
						{ label: '音声解析から音色JSONを作る', slug: 'implementation/audio-analysis' },
					],
				},
				{
					label: '詳細：ファームウェア',
					collapsed: true,
					items: [
						{ label: '読み順ガイド', slug: 'firmware' },
						{ label: 'IModule', slug: 'firmware/imodule' },
						{ label: 'OrcProtocol', slug: 'firmware/orc-protocol' },
						{ label: 'OrcNetModule', slug: 'firmware/orc-net' },
						{ label: 'StatusLedModule', slug: 'firmware/status-led' },
						{ label: 'SerialDebug', slug: 'firmware/serial-debug' },
						{ label: 'ImuModule', slug: 'firmware/imu-module' },
						{ label: 'OrcSenderModule', slug: 'firmware/orc-sender' },
						{ label: 'OrcReceiverModule', slug: 'firmware/orc-receiver' },
						{ label: 'NoteSenderModule', slug: 'firmware/note-sender' },
						{ label: 'UiRelayModule', slug: 'firmware/ui-relay' },
						{ label: '指揮者main', slug: 'firmware/main-conductor' },
						{ label: '楽器main', slug: 'firmware/main-instrument' },
					],
				},
				{
					label: '詳細：アルゴリズム・数式',
					collapsed: true,
					items: [
						{ label: '読み順ガイド', slug: 'deep-dive' },
						{ label: '拍検出', slug: 'deep-dive/beat-detection' },
						{ label: '時刻同期', slug: 'deep-dive/time-sync' },
						{ label: 'UDPマルチキャスト', slug: 'deep-dive/udp-multicast' },
						{ label: 'バイナリパケット', slug: 'deep-dive/binary-packet' },
						{ label: '楽譜進行', slug: 'deep-dive/score-progression' },
						{ label: 'ゲーム操作と採点', slug: 'deep-dive/game-navigation-scoring' },
						{ label: '加算合成', slug: 'deep-dive/additive-synthesis' },
						{ label: 'モジュール拡張', slug: 'deep-dive/module-extension' },
					],
				},
				{
					label: '詳細：PC・音声処理',
					collapsed: true,
					items: [
						{ label: '読み順ガイド', slug: 'pc-audio' },
						{ label: '設計判断', slug: 'pc-audio/design' },
						{ label: '信号フロー', slug: 'pc-audio/signal-flow' },
						{ label: 'メインスケッチ', slug: 'pc-audio/resynth-main' },
						{ label: 'PC側OrcProtocol', slug: 'pc-audio/orc-protocol' },
						{ label: 'SerialCore', slug: 'pc-audio/serial-handling' },
						{ label: 'AudioManager', slug: 'pc-audio/audio-manager' },
						{ label: 'InstrModel', slug: 'pc-audio/instr-model' },
						{ label: 'ResynthVoice', slug: 'pc-audio/resynth-voice' },
						{ label: 'DrumEngine', slug: 'pc-audio/drum-engine' },
						{ label: 'SharedUI', slug: 'pc-audio/shared-ui' },
						{ label: 'OrcLogger', slug: 'pc-audio/orc-logger' },
						{ label: '音声解析全体', slug: 'pc-audio/analyzer-overview' },
						{ label: '倍音・ノイズ解析', slug: 'pc-audio/analyzer-harmonics' },
						{ label: '基音・ADSR・変調', slug: 'pc-audio/analyzer-modulation' },
						{ label: '別方式への拡張', slug: 'pc-audio/extending' },
					],
				},
				{
					label: '意思決定の記録（ADR）',
					items: [{ autogenerate: { directory: 'decisions' } }],
				},
				{
					label: '開発履歴・記録',
					items: [
						{ label: 'バージョン変遷', slug: 'history/versions' },
						{ label: 'test_v1の記録', slug: 'history/test-v1' },
						{ label: 'test_v2の記録', slug: 'history/test-v2' },
						{ label: 'チーム役割', slug: 'history/roles' },
						{ label: '授業・開発スケジュール', slug: 'history/schedule' },
					],
				},
			],
		}),
	],
});
