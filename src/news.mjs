import { XMLParser } from 'fast-xml-parser';
import * as cheerio from 'cheerio';

const FEED_HEADERS = {
  'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0 Safari/537.36',
  accept: 'application/rss+xml, application/xml, text/xml, text/html;q=0.9, */*;q=0.8',
};

const parser = new XMLParser({
  ignoreAttributes: false,
  parseTagValue: false,
  trimValues: true,
});

const NEGATIVE_PATTERNS = [
  /\bnews live\b/i,
  /\blive blog\b/i,
  /\bbasketball\b/i,
  /\bfootball\b/i,
  /\bsoccer\b/i,
  /\bbaseball\b/i,
  /\btennis\b/i,
  /\bgolf\b/i,
  /\bfashion\b/i,
  /\bshoe(s)?\b/i,
  /\bsneaker(s)?\b/i,
  /\bcelebrity\b/i,
  /\bmovie\b/i,
  /\bmusic\b/i,
  /\bentertainment\b/i,
];

const KEYWORD_WEIGHTS = new Map([
  ['war', 3.8],
  ['military', 3.8],
  ['defense', 3.8],
  ['defence', 3.8],
  ['missile', 4.3],
  ['drone', 4.0],
  ['nuclear', 4.4],
  ['air strike', 4.2],
  ['strike', 2.7],
  ['troops', 3.5],
  ['troop', 3.2],
  ['warship', 4.1],
  ['naval', 3.1],
  ['navy', 3.0],
  ['air force', 3.0],
  ['army', 2.9],
  ['fighter jet', 3.7],
  ['ceasefire', 3.8],
  ['conflict', 3.2],
  ['invasion', 4.1],
  ['sanction', 4.0],
  ['sanctions', 4.0],
  ['foreign policy', 3.8],
  ['diplomacy', 3.3],
  ['diplomatic', 3.2],
  ['talks', 2.6],
  ['summit', 3.5],
  ['nato', 4.1],
  ['un', 2.4],
  ['united nations', 3.1],
  ['president', 2.6],
  ['prime minister', 3.0],
  ['defense minister', 3.2],
  ['foreign minister', 3.1],
  ['parliament', 2.4],
  ['congress', 2.1],
  ['election', 2.4],
  ['cabinet', 2.3],
  ['coalition', 2.6],
  ['taiwan', 4.2],
  ['ukraine', 4.6],
  ['russia', 4.1],
  ['iran', 4.0],
  ['israel', 4.0],
  ['gaza', 3.9],
  ['china', 3.5],
  ['south china sea', 4.2],
  ['north korea', 4.0],
  ['syria', 3.0],
  ['cyprus', 2.5],
  ['indo-pacific', 3.4],
  ['allies', 2.6],
  ['alliance', 2.9],
  ['security', 2.4],
]);

const SOURCE_WEIGHTS = new Map([
  ['bbc.com', 8.8],
  ['bbc.co.uk', 8.8],
  ['theguardian.com', 8.3],
  ['nytimes.com', 8.7],
  ['defensenews.com', 9.0],
]);

function toArray(value) {
  if (!value) {
    return [];
  }

  return Array.isArray(value) ? value : [value];
}

function textOf(value) {
  if (value == null) {
    return '';
  }

  if (typeof value === 'string') {
    return value;
  }

  if (Array.isArray(value)) {
    return value.map(textOf).filter(Boolean).join(' ');
  }

  if (typeof value === 'object') {
    return Object.values(value).map(textOf).filter(Boolean).join(' ');
  }

  return String(value);
}

function htmlToText(html) {
  if (!html) {
    return '';
  }

  const $ = cheerio.load(`<div>${html}</div>`);
  $('script, style').remove();
  return $('div').text().replace(/\s+/g, ' ').trim();
}

function cleanText(text) {
  return text.replace(/\s+/g, ' ').trim();
}

function normalizeUrl(rawUrl) {
  try {
    const url = new URL(rawUrl);
    const removableKeys = [];

    for (const [key] of url.searchParams.entries()) {
      if (
        key.startsWith('utm_') ||
        key === 'CMP' ||
        key === 'cmpid' ||
        key === 'fbclid' ||
        key === 'gclid' ||
        key === 'smid' ||
        key === 'taid'
      ) {
        removableKeys.push(key);
      }
    }

    for (const key of removableKeys) {
      url.searchParams.delete(key);
    }

    url.hash = '';
    return url.toString();
  } catch {
    return rawUrl;
  }
}

function getHostname(link) {
  try {
    const { hostname } = new URL(link);
    return hostname.replace(/^www\./i, '');
  } catch {
    return '';
  }
}

function countKeywordHits(text, keyword) {
  const pattern = keyword.includes(' ')
    ? new RegExp(keyword.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi')
    : new RegExp(`\\b${keyword.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'gi');
  return (text.match(pattern) || []).length;
}

function computeScore(article, lookbackHours) {
  const combined = `${article.title} ${article.summary}`.toLowerCase();

  for (const pattern of NEGATIVE_PATTERNS) {
    if (pattern.test(combined)) {
      return Number.NEGATIVE_INFINITY;
    }
  }

  let keywordScore = 0;
  let matchedTerms = 0;

  for (const [keyword, weight] of KEYWORD_WEIGHTS.entries()) {
    const hits = countKeywordHits(combined, keyword);
    if (hits > 0) {
      keywordScore += Math.min(2, hits) * weight;
      matchedTerms += 1;
    }
  }

  if (matchedTerms < 2) {
    return Number.NEGATIVE_INFINITY;
  }

  const sourceWeight = SOURCE_WEIGHTS.get(article.hostname) ?? article.feedWeight;
  const hoursSincePublished = Math.max(
    0,
    (Date.now() - article.publishedAt.getTime()) / (1000 * 60 * 60),
  );
  const freshnessScore = Math.max(0, 7 - (hoursSincePublished / Math.max(lookbackHours, 1)) * 7);
  const descriptionBonus = Math.min(2.5, article.summary.length / 240);
  const opinionPenalty = /\b(opinion|analysis|podcast|newsletter|live)\b/i.test(combined) ? 2.5 : 0;

  return sourceWeight + keywordScore + freshnessScore + descriptionBonus - opinionPenalty;
}

async function fetchWithTimeout(url, timeoutMs = 20000) {
  const response = await fetch(url, {
    headers: FEED_HEADERS,
    signal: AbortSignal.timeout(timeoutMs),
  });

  if (!response.ok) {
    throw new Error(`请求失败: ${response.status} ${response.statusText}`);
  }

  return response;
}

async function fetchFeed(feed) {
  const response = await fetchWithTimeout(feed.url);
  const xml = await response.text();
  const parsed = parser.parse(xml);
  const rawItems = toArray(parsed?.rss?.channel?.item ?? parsed?.feed?.entry);

  return rawItems
    .map((item) => {
      const linkValue = item.link?.href ?? item.link;
      const link = normalizeUrl(textOf(linkValue));
      const title = cleanText(textOf(item.title));
      const description = cleanText(htmlToText(textOf(item.description)));
      const content = cleanText(htmlToText(textOf(item['content:encoded'])));
      const summary = content || description;
      const publishedText = textOf(item.pubDate || item.published || item.updated || item['dc:date']);
      const publishedAt = publishedText ? new Date(publishedText) : null;

      if (!link || !title || !publishedAt || Number.isNaN(publishedAt.getTime())) {
        return null;
      }

      return {
        id: link,
        title,
        link,
        source: feed.name,
        hostname: getHostname(link),
        summary,
        publishedAt,
        feedWeight: feed.feedWeight,
      };
    })
    .filter(Boolean);
}

async function enrichArticles(articles) {
  const targets = articles.filter((article) => article.summary.length < 180).slice(0, 8);

  await Promise.allSettled(
    targets.map(async (article) => {
      try {
        const response = await fetchWithTimeout(article.link, 15000);
        const html = await response.text();
        const $ = cheerio.load(html);

        const metaDescription =
          $('meta[property="og:description"]').attr('content') ||
          $('meta[name="description"]').attr('content') ||
          '';

        const paragraphText = $('article p, main p')
          .slice(0, 6)
          .toArray()
          .map((node) => $(node).text())
          .join(' ');

        const enriched = cleanText(`${metaDescription} ${paragraphText}`);
        if (enriched.length > article.summary.length) {
          article.summary = enriched;
        }
      } catch {
        // Keep feed summary when article enrichment fails.
      }
    }),
  );
}

export async function collectCandidateArticles(config, state) {
  const settledFeeds = await Promise.allSettled(
    config.news.feeds.map((feed) => fetchFeed(feed)),
  );

  const deduped = new Map();
  const cutoff = Date.now() - config.news.lookbackHours * 60 * 60 * 1000;
  const sentLinks = state.sentLinks ?? {};

  for (const result of settledFeeds) {
    if (result.status !== 'fulfilled') {
      continue;
    }

    for (const article of result.value) {
      if (article.publishedAt.getTime() < cutoff) {
        continue;
      }

      const alreadySentAt = sentLinks[article.link];
      if (alreadySentAt) {
        continue;
      }

      const existing = deduped.get(article.link);
      if (!existing || existing.feedWeight < article.feedWeight) {
        deduped.set(article.link, article);
      }
    }
  }

  const articles = [...deduped.values()];
  await enrichArticles(articles);

  return articles
    .map((article) => ({
      ...article,
      score: computeScore(article, config.news.lookbackHours),
      excerpt: article.summary.slice(0, 900),
    }))
    .filter((article) => Number.isFinite(article.score))
    .sort((left, right) => right.score - left.score)
    .slice(0, Math.max(config.news.candidateLimit, config.news.storyCount));
}
