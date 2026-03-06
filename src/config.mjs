import path from 'node:path';
import process from 'node:process';
import dotenv from 'dotenv';

dotenv.config({ quiet: true });

export const FEEDS = [
  {
    name: 'BBC World',
    url: 'https://feeds.bbci.co.uk/news/world/rss.xml',
    feedWeight: 8.8,
  },
  {
    name: 'BBC Politics',
    url: 'https://feeds.bbci.co.uk/news/politics/rss.xml',
    feedWeight: 8.2,
  },
  {
    name: 'The Guardian World',
    url: 'https://www.theguardian.com/world/rss',
    feedWeight: 8.4,
  },
  {
    name: 'The Guardian Politics',
    url: 'https://www.theguardian.com/politics/rss',
    feedWeight: 8.0,
  },
  {
    name: 'NYT World',
    url: 'https://rss.nytimes.com/services/xml/rss/nyt/World.xml',
    feedWeight: 8.7,
  },
  {
    name: 'NYT Politics',
    url: 'https://rss.nytimes.com/services/xml/rss/nyt/Politics.xml',
    feedWeight: 8.3,
  },
  {
    name: 'Defense News Global',
    url: 'https://www.defensenews.com/arc/outboundfeeds/rss/category/global/?outputType=xml',
    feedWeight: 9.0,
  },
  {
    name: 'Defense News Pentagon',
    url: 'https://www.defensenews.com/arc/outboundfeeds/rss/category/pentagon/?outputType=xml',
    feedWeight: 8.7,
  },
];

function readRequired(name) {
  const value = process.env[name]?.trim();
  return value || '';
}

function readInt(name, fallback) {
  const raw = process.env[name]?.trim();
  if (!raw) {
    return fallback;
  }

  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function readProvider() {
  const value = (process.env.LLM_PROVIDER || 'openai').trim().toLowerCase();
  return value === 'deepseek' ? 'deepseek' : 'openai';
}

export function loadConfig() {
  const cwd = process.cwd();
  const provider = readProvider();
  const openaiApiKey = readRequired('OPENAI_API_KEY');
  const deepseekApiKey = readRequired('DEEPSEEK_API_KEY');

  return {
    cwd,
    timezone: readRequired('TIMEZONE') || 'Asia/Shanghai',
    llm: {
      provider,
      apiKey: provider === 'deepseek' ? deepseekApiKey : openaiApiKey,
      model:
        provider === 'deepseek'
          ? readRequired('DEEPSEEK_MODEL') || 'deepseek-chat'
          : readRequired('OPENAI_MODEL') || 'gpt-5-mini',
      baseUrl:
        provider === 'deepseek'
          ? readRequired('DEEPSEEK_BASE_URL') || 'https://api.deepseek.com'
          : readRequired('OPENAI_BASE_URL'),
    },
    qq: {
      baseUrl: readRequired('QQ_API_BASE_URL'),
      sendGroupPath: readRequired('QQ_SEND_GROUP_PATH') || '/send_group_msg',
      accessToken: readRequired('QQ_API_ACCESS_TOKEN'),
      groupId: readRequired('QQ_GROUP_ID'),
    },
    news: {
      lookbackHours: readInt('NEWS_LOOKBACK_HOURS', 36),
      candidateLimit: readInt('NEWS_CANDIDATE_LIMIT', 18),
      storyCount: readInt('NEWS_STORY_COUNT', 5),
      stateRetentionDays: readInt('STATE_RETENTION_DAYS', 7),
      feeds: FEEDS,
    },
    paths: {
      stateFile: path.join(cwd, 'data', 'state.json'),
    },
  };
}

export function validateConfig(config, flags) {
  const missing = [];

  if (!config.llm.apiKey && !flags.previewCandidates) {
    missing.push(config.llm.provider === 'deepseek' ? 'DEEPSEEK_API_KEY' : 'OPENAI_API_KEY');
  }

  if (!flags.previewCandidates && !flags.dryRun) {
    if (!config.qq.baseUrl) {
      missing.push('QQ_API_BASE_URL');
    }

    if (!config.qq.groupId) {
      missing.push('QQ_GROUP_ID');
    }
  }

  if (missing.length > 0) {
    throw new Error(`Missing required config: ${missing.join(', ')}`);
  }
}
