import OpenAI from 'openai';

function stripCodeFence(text) {
  return text
    .replace(/^```(?:json)?/i, '')
    .replace(/```$/i, '')
    .trim();
}

function extractJson(text) {
  const cleaned = stripCodeFence(text);
  const start = cleaned.indexOf('{');
  const end = cleaned.lastIndexOf('}');

  if (start < 0 || end < 0 || end <= start) {
    throw new Error('Model response did not contain valid JSON.');
  }

  return JSON.parse(cleaned.slice(start, end + 1));
}

function clipChars(text, maxChars) {
  const chars = Array.from(text.trim());
  return chars.length <= maxChars ? chars.join('') : `${chars.slice(0, maxChars).join('')}...`;
}

function buildInstructions() {
  return [
    'You are the editor of a Chinese military and geopolitics morning briefing.',
    'Choose the 5 most globally impactful stories from the candidate list.',
    'Prioritize war escalation, military deployment, alliance changes, sanctions, diplomacy, major state decisions, and cross-border security risk.',
    'Ignore sports, entertainment, consumer news, local soft news, marketing copy, and human-interest features.',
    'Each summary_zh must be a single objective Simplified Chinese paragraph with about 130 to 150 Chinese characters.',
    'Do not include source names, links, numbering, quotes, book-title marks, or the original headline wording.',
    'Do not start with phrases like "according to reports".',
    'Return strict JSON only in this format: {"selected":[{"id":"story_1","rank":1,"summary_zh":"..."}]}.',
    'Return exactly 5 items, and every id must come from the candidate list.',
  ].join('\n');
}

function buildClient(config) {
  const options = {
    apiKey: config.llm.apiKey,
    timeout: 120000,
    maxRetries: 2,
  };

  if (config.llm.baseUrl) {
    options.baseURL = config.llm.baseUrl;
  }

  return new OpenAI(options);
}

async function runDeepSeek(client, config, instructions, shortlist) {
  const completion = await client.chat.completions.create({
    model: config.llm.model,
    response_format: { type: 'json_object' },
    messages: [
      { role: 'system', content: instructions },
      { role: 'user', content: JSON.stringify({ candidates: shortlist }, null, 2) },
    ],
    max_tokens: 2400,
    stream: false,
  });

  return completion.choices[0]?.message?.content || '';
}

async function runOpenAI(client, config, instructions, shortlist) {
  const response = await client.responses.create({
    model: config.llm.model,
    instructions,
    input: JSON.stringify({ candidates: shortlist }, null, 2),
    max_output_tokens: 2400,
  });

  return response.output_text;
}

export async function selectStoriesWithModel(candidates, config) {
  const client = buildClient(config);
  const instructions = buildInstructions();

  const shortlist = candidates.slice(0, config.news.candidateLimit).map((candidate, index) => ({
    id: `story_${index + 1}`,
    title: candidate.title,
    source: candidate.source,
    url: candidate.link,
    published_at: candidate.publishedAt.toISOString(),
    heuristic_score: Number(candidate.score.toFixed(2)),
    excerpt: clipChars(candidate.excerpt, 700),
  }));

  const rawText =
    config.llm.provider === 'deepseek'
      ? await runDeepSeek(client, config, instructions, shortlist)
      : await runOpenAI(client, config, instructions, shortlist);

  const parsed = extractJson(rawText);
  const selected = Array.isArray(parsed.selected) ? parsed.selected : [];

  if (selected.length !== config.news.storyCount) {
    throw new Error(
      `Model returned ${selected.length} items, expected ${config.news.storyCount}.`,
    );
  }

  const byId = new Map(shortlist.map((candidate) => [candidate.id, candidate]));

  return selected
    .map((item) => {
      const base = byId.get(item.id);
      if (!base) {
        throw new Error(`Model returned an unknown id: ${item.id}`);
      }

      return {
        id: item.id,
        rank: Number(item.rank) || 99,
        title: base.title,
        source: base.source,
        link: base.url,
        summary: clipChars(String(item.summary_zh || '').replace(/\s+/g, ' ').trim(), 150),
      };
    })
    .sort((left, right) => left.rank - right.rank);
}
