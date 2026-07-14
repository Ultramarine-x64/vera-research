-- Citeproc + ScalAR-inspired publication cards + optional extras.

local META_PATH = "publications-meta.yml"

local function has_class(el, name)
  for _, class in ipairs(el.classes) do
    if class == name then
      return true
    end
  end
  return false
end

local function is_entry(block)
  return has_class(block, "csl-entry")
    or (block.identifier and block.identifier:match("^ref%-"))
end

local function meta_string(value)
  if value == nil then
    return nil
  end
  if type(value) == "string" then
    if value == "" then
      return nil
    end
    return value
  end
  if type(value) == "number" then
    return tostring(value)
  end
  local text = pandoc.utils.stringify(value)
  if text == "" then
    return nil
  end
  return text
end

local function resolve_meta_path()
  local function parent_dir(d)
    return d and d:match("(.+)/[^/]+$") or nil
  end

  local function dir_of(path)
    if not path then
      return nil
    end
    return path:match("(.+)/[^/]+$") or nil
  end

  local function join(a, b)
    if not a or a == "" then
      return b
    end
    if a:sub(-1) == "/" then
      return a .. b
    end
    return a .. "/" .. b
  end

  local candidates = { META_PATH }

  local wd = pandoc.system and pandoc.system.get_working_directory and pandoc.system.get_working_directory() or nil
  if wd then
    table.insert(candidates, join(wd, META_PATH))
  end

  local info = debug and debug.getinfo and debug.getinfo(1, "S") or nil
  local src = info and info.source or nil
  if type(src) == "string" and src:sub(1, 1) == "@" then
    local filter_path = src:sub(2)
    local filter_dir = dir_of(filter_path)
    local repo_root = parent_dir(filter_dir)
    if repo_root then
      table.insert(candidates, join(repo_root, META_PATH))
    end
  end

  for _, p in ipairs(candidates) do
    local f = io.open(p, "r")
    if f then
      f:close()
      return p
    end
  end

  return META_PATH
end

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parse_publications_meta(contents)
  local result = {}
  local current_key = nil

  for line in contents:gmatch("[^\r\n]+") do
    if not line:match("^%s*#") then
      local top_key = line:match("^([%w%-]+):%s*$")
      if top_key then
        current_key = top_key
        result[current_key] = {}
      else
        local field, value = line:match("^%s+([%w%-]+):%s*(.-)%s*$")
        if current_key and field and value ~= "" then
          result[current_key][field] = trim(value)
        end
      end
    end
  end

  return result
end

local function load_publications_meta()
  local path = resolve_meta_path()
  local file = io.open(path, "r")
  if not file then
    return {}
  end
  local contents = file:read("*a")
  file:close()
  return parse_publications_meta(contents)
end

local function cite_key(entry_id)
  return (entry_id or ""):gsub("^ref%-", "")
end

local function build_ref_index(doc)
  local index = {}
  for _, ref in ipairs(pandoc.utils.references(doc)) do
    if ref.id then
      index[ref.id] = ref
    end
  end
  return index
end

local function ref_year(ref)
  if not ref or not ref.issued then
    return nil
  end

  local issued = ref.issued
  if type(issued) == "string" or type(issued) == "number" then
    return tostring(issued)
  end

  if type(issued) == "table" then
    local date_parts = issued["date-parts"]
    if type(date_parts) == "table" and date_parts[1] then
      local part = date_parts[1]
      if type(part) == "table" and part[1] then
        return tostring(part[1])
      end
      if type(part) == "number" or type(part) == "string" then
        return tostring(part)
      end
    end
  end

  return nil
end

local function initial_from_given(given)
  if not given or given == "" then
    return nil
  end
  local parts = {}
  for token in given:gmatch("%S+") do
    local ch = token:match("[%z\1-\127\194-\244][\128-\191]*")
    if ch then
      table.insert(parts, ch:upper() .. ".")
    end
  end
  if #parts == 0 then
    return nil
  end
  return table.concat(parts, " ")
end

local function format_author_name(author)
  local family = meta_string(author.family) or ""
  local given = meta_string(author.given)
  local initials = initial_from_given(given)
  if initials and family ~= "" then
    return initials .. " " .. family
  end
  if family ~= "" then
    return family
  end
  return pandoc.utils.stringify(author)
end

local function format_authors(ref)
  if not ref or not ref.author then
    return nil
  end

  local names = {}
  for _, author in ipairs(ref.author) do
    table.insert(names, format_author_name(author))
  end

  if #names == 0 then
    return nil
  end
  if #names == 1 then
    return names[1]
  end
  if #names == 2 then
    return names[1] .. " and " .. names[2]
  end

  local head = table.concat(names, ", ", 1, #names - 1)
  return head .. ", and " .. names[#names]
end

local function format_venue(ref, year)
  if not ref then
    return nil
  end

  local parts = {}
  local journal = meta_string(ref["container-title"])
  if journal then
    table.insert(parts, journal)
  end

  local volume = meta_string(ref.volume)
  if volume then
    table.insert(parts, "vol. " .. volume)
  end

  local issue = meta_string(ref.issue)
  if issue then
    table.insert(parts, "no. " .. issue)
  end

  local page = meta_string(ref.page)
  if page then
    if page:match("^%d+$") then
      table.insert(parts, "p. " .. page)
    else
      table.insert(parts, "pp. " .. page)
    end
  end

  if year then
    table.insert(parts, year)
  end

  if #parts == 0 then
    return nil
  end
  return table.concat(parts, ", ")
end

local function doi_url(doi)
  if not doi then
    return nil
  end
  if doi:match("^https?://") then
    return doi
  end
  return "https://doi.org/" .. doi
end

local function entry_extras(key, ref, meta)
  local entry = meta[key]
  local extras = {
    quartile = entry and entry.quartile or nil,
    code = entry and entry.code or nil,
    video = entry and entry.video or nil,
    doi = (entry and entry.doi)
      or (ref and meta_string(ref.doi))
      or nil,
  }
  return extras
end

local function link_separator()
  return { pandoc.Space(), pandoc.Str("·"), pandoc.Space() }
end

local function build_links_inlines(extras)
  local links = {}
  local url = doi_url(extras.doi)
  if url then
    table.insert(links, pandoc.Link("DOI", url))
  end
  if extras.code then
    table.insert(links, pandoc.Link("Code", extras.code))
  end
  if extras.video then
    table.insert(links, pandoc.Link("Video", extras.video))
  end

  if #links == 0 then
    return nil
  end

  local inlines = {}
  for i, link in ipairs(links) do
    if i > 1 then
      for _, sep in ipairs(link_separator()) do
        table.insert(inlines, sep)
      end
    end
    table.insert(inlines, link)
  end
  return inlines
end

local function build_footer(extras)
  local footer_blocks = {}
  local link_inlines = build_links_inlines(extras)

  if not extras.quartile and not link_inlines then
    return nil
  end

  if extras.quartile then
    table.insert(
      footer_blocks,
      pandoc.Div(
        { pandoc.Plain({ pandoc.Str(extras.quartile) }) },
        pandoc.Attr("", { "vera-pub-meta" }, {})
      )
    )
  end

  if link_inlines then
    table.insert(
      footer_blocks,
      pandoc.Div(
        { pandoc.Plain(link_inlines) },
        pandoc.Attr("", { "vera-pub-links" }, {})
      )
    )
  end

  return pandoc.Div(footer_blocks, pandoc.Attr("", { "vera-pub-footer" }, {}))
end

local function plain_div(text, class_name)
  return pandoc.Div(
    { pandoc.Plain({ pandoc.Str(text) }) },
    pandoc.Attr("", { class_name }, {})
  )
end

local function transform_entry(entry, ref_index, meta)
  local key = cite_key(entry.identifier)
  local ref = ref_index[key]
  if not ref then
    return entry
  end

  local year = ref_year(ref) or ""
  local title = meta_string(ref.title)
  local authors = format_authors(ref)
  local venue = format_venue(ref, year)
  local extras = entry_extras(key, ref, meta)

  local content_blocks = {}
  if title then
    table.insert(content_blocks, plain_div(title, "vera-pub-title"))
  end
  if authors then
    table.insert(content_blocks, plain_div(authors, "vera-pub-authors"))
  end
  if venue then
    table.insert(content_blocks, plain_div(venue, "vera-pub-venue"))
  end

  local pub_blocks = {
    pandoc.Div(
      {
        plain_div(year, "vera-pub-year"),
        pandoc.Div(content_blocks, pandoc.Attr("", { "vera-pub-content" }, {})),
      },
      pandoc.Attr("", { "vera-pub-main" }, {})
    ),
  }

  local footer = build_footer(extras)
  if footer then
    table.insert(pub_blocks, footer)
  end

  return pandoc.Div(pub_blocks, pandoc.Attr(entry.identifier, { "vera-pub" }, {}))
end

local function walk_blocks(blocks, ref_index, meta)
  local out = {}
  for _, block in ipairs(blocks) do
    if block.t == "Div" then
      if block.identifier == "refs" or has_class(block, "references") then
        block.classes:insert("vera-pub-list")
        block.content = walk_blocks(block.content, ref_index, meta)
      elseif is_entry(block) then
        block = transform_entry(block, ref_index, meta)
      else
        block.content = walk_blocks(block.content, ref_index, meta)
      end
    end
    table.insert(out, block)
  end
  return out
end

function Pandoc(doc)
  doc = pandoc.utils.citeproc(doc)
  local meta = load_publications_meta()
  local ref_index = build_ref_index(doc)
  doc.blocks = walk_blocks(doc.blocks, ref_index, meta)
  return doc
end
