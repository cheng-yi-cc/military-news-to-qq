import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { loadConfig, validateConfig } from './config.mjs';
import { collectCandidateArticles } from './news.mjs';
import { selectStoriesWithModel } from './openai-client.mjs';

function parseFlags(argv) {
  const flags = new Set(argv);
  return {
    dryRun: flags.has('--dry-run'),
    previewCandidates: flags.has('--preview-candidates'),
    force: flags.has('--force'),
  };
}

async function ensureParentDir(filePath) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
}

async function loadState(filePath) {
  try {
    const raw = await fs.readFile(filePath, 'utf8');
    return JSON.parse(raw);
  } catch (error) {
    if (error?.code === 'ENOENT') {
      return {
        sentLinks: {},
        dailyRuns: {},
      };
    }

    throw error;
  }
}

function pruneState(state, config) {
  const cutoff = Date.now() - config.news.stateRetentionDays * 24 * 60 * 60 * 1000;
  const nextSentLinks = {};

  for (const [link, timestamp] of Object.entries(state.sentLinks ?? {})) {
    const time = new Date(timestamp).getTime();
    if (Number.isFinite(time) && time >= cutoff) {
      nextSentLinks[link] = timestamp;
    }
  }

  state.sentLinks = nextSentLinks;
}

async function saveState(filePath, state) {
  await ensureParentDir(filePath);
  await fs.writeFile(filePath, JSON.stringify(state, null, 2), 'utf8');
}

function formatDateKey(date, timeZone) {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });

  return formatter.format(date);
}

function formatHeaderTime(date, timeZone) {
  return new Intl.DateTimeFormat('zh-CN', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(date);
}

function buildMessage(stories, config) {
  const headerTime = formatHeaderTime(new Date(), config.timezone);
  const lines = [
    `【全球军事时政早报｜${headerTime}】`,
    `范围：近 ${config.news.lookbackHours} 小时全球军事与国际时政动态`,
    '',
  ];

  for (const [index, story] of stories.entries()) {
    lines.push(`${index + 1}. ${story.title}`);
    lines.push(`摘要：${story.summary}`);
    lines.push(`出处：${story.source}`);
    lines.push(`链接：${story.link}`);
    lines.push('');
  }

  return lines.join('\n').trim();
}

function buildPreview(candidates) {
  return candidates
    .map((candidate, index) => {
      const published = candidate.publishedAt.toISOString();
      return [
        `${index + 1}. [${candidate.score.toFixed(2)}] ${candidate.title}`,
        `   来源：${candidate.source}`,
        `   时间：${published}`,
        `   链接：${candidate.link}`,
      ].join('\n');
    })
    .join('\n\n');
}

function buildQqEndpoint(baseUrl, sendGroupPath) {
  const normalizedBase = baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`;
  return new URL(sendGroupPath.replace(/^\//, ''), normalizedBase).toString();
}

async function sendToQq(message, config) {
  const endpoint = buildQqEndpoint(config.qq.baseUrl, config.qq.sendGroupPath);
  const headers = {
    'content-type': 'application/json',
  };

  if (config.qq.accessToken) {
    headers.Authorization = `Bearer ${config.qq.accessToken}`;
  }

  const response = await fetch(endpoint, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      group_id: /^\d+$/.test(config.qq.groupId) ? Number(config.qq.groupId) : config.qq.groupId,
      message,
      auto_escape: false,
    }),
    signal: AbortSignal.timeout(15000),
  });

  if (!response.ok) {
    throw new Error(`QQ 发送失败: ${response.status} ${response.statusText}`);
  }

  const text = await response.text();
  if (!text) {
    return;
  }

  try {
    const payload = JSON.parse(text);
    if (payload.status === 'failed' || (payload.retcode != null && payload.retcode !== 0)) {
      throw new Error(text);
    }
  } catch (error) {
    if (error instanceof SyntaxError) {
      return;
    }

    throw new Error(`QQ 接口返回异常: ${error.message}`);
  }
}

async function main() {
  const flags = parseFlags(process.argv.slice(2));
  const config = loadConfig();
  validateConfig(config, flags);

  const state = await loadState(config.paths.stateFile);
  pruneState(state, config);

  const todayKey = formatDateKey(new Date(), config.timezone);
  if (!flags.previewCandidates && !flags.dryRun && !flags.force && state.dailyRuns?.[todayKey]) {
    console.log(`今天已发送过早报（${todayKey}），如需强制重发请加 --force。`);
    return;
  }

  const candidates = await collectCandidateArticles(config, state);
  if (candidates.length < config.news.storyCount) {
    throw new Error(`候选新闻不足，仅找到 ${candidates.length} 条有效候选。`);
  }

  if (flags.previewCandidates) {
    console.log(buildPreview(candidates));
    return;
  }

  const stories = await selectStoriesWithModel(candidates, config);
  const message = buildMessage(stories, config);

  if (flags.dryRun) {
    console.log(message);
    return;
  }

  await sendToQq(message, config);

  const sentAt = new Date().toISOString();
  for (const story of stories) {
    state.sentLinks[story.link] = sentAt;
  }

  state.dailyRuns[todayKey] = {
    sentAt,
    links: stories.map((story) => story.link),
  };

  await saveState(config.paths.stateFile, state);
  console.log(`已发送 ${stories.length} 条新闻到 QQ 群 ${config.qq.groupId}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
