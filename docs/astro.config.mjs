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
					label: 'コンセプト',
					items: [
						{ label: 'なぜ作るのか', slug: 'concept/why' },
						{ label: 'シナリオと体験', slug: 'concept/scenario' },
						{ label: 'ゴールとスコープ', slug: 'concept/goals' },
					],
				},
				{
					label: 'アーキテクチャ',
					items: [
						{ label: '全体図', slug: 'architecture/overview' },
						{ label: 'Embedded-Module-Architecture', slug: 'architecture/ema' },
						{ label: '通信プロトコル（UDP）', slug: 'architecture/protocol' },
						{ label: '楽譜フォーマット', slug: 'architecture/score' },
						{ label: '同期戦略（±20ms）', slug: 'architecture/sync' },
						{ label: '三段階開発', slug: 'architecture/three-stages' },
					],
				},
				{
					label: '開発ガイド',
					items: [
						{ label: '必要なものをそろえる', slug: 'guide/setup' },
						{ label: 'リポジトリを手元に持ってくる', slug: 'guide/clone' },
						{ label: 'Arduino を書き換える', slug: 'guide/firmware' },
						{ label: 'PC アプリを動かす', slug: 'guide/processing' },
						{ label: 'シリアルモニタでデバッグする', slug: 'guide/debug' },
						{ label: 'LaTeX 報告書をコンパイルする', slug: 'guide/latex' },
						{ label: 'チームで Git を使う', slug: 'guide/git' },
					],
				},
				{
					label: 'コードを読む',
					items: [
						{ label: 'リポジトリ・マップ', slug: 'code/map' },
						{ label: 'firmware の歩き方', slug: 'code/firmware' },
						{ label: 'pc_app の歩き方', slug: 'code/pc-app' },
						{ label: 'test_v1 / test_v2 / production の差分', slug: 'code/versions' },
						{ label: 'よく出るトラブルと対処', slug: 'code/troubleshooting' },
					],
				},
				{
					label: '意思決定の記録（ADR）',
					items: [{ autogenerate: { directory: 'decisions' } }],
				},
				{
					label: '役割と運用',
					items: [
						{ label: 'チーム役割', slug: 'team/roles' },
						{ label: 'ミーティングと提出スケジュール', slug: 'team/schedule' },
					],
				},
			],
		}),
	],
});
