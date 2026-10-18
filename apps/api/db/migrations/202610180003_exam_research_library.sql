-- 官方资料本地库：把从官方域名抓取过的页面原文，以及搜索命中的官方链接持久化。
-- 之后同一目标再次核实、或访谈目标逐渐补充（院校/专业/年份变化）时，优先复用本地内容，
-- 只重新抓取资料库里缺失或过期的部分，避免每次访谈都整轮联网搜索 + 抓取。
create table if not exists exam_research_documents (
  url text primary key,
  title text not null default '',
  text text not null default '',
  links jsonb not null default '[]'::jsonb,
  fetched_at timestamptz not null default now(),
  last_used_at timestamptz not null default now()
);

create table if not exists exam_research_searches (
  search_query text primary key,
  urls jsonb not null default '[]'::jsonb,
  searched_at timestamptz not null default now(),
  last_used_at timestamptz not null default now()
);

create index if not exists exam_research_documents_used_idx on exam_research_documents (last_used_at);
create index if not exists exam_research_searches_used_idx on exam_research_searches (last_used_at);
