-- Citeproc + ScalAR-inspired publication cards + category sections.

local META_PATH = "publications-meta.yml"
local FIELD_PATTERN = "[%w_%-]+"

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
    or has_class(block, "vera-pub")
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

local function unquote(value)
  value = trim(value)
  local quoted = value:match([[^"(.*)"$]]) or value:match([[^'(.*)'$]])
  return quoted or value
end

local function parse_publications_meta(contents)
  local result = {
    entries = {},
    category_order = {},
    category_labels = {},
    default_category = nil,
  }

  local current_key = nil
  local current_mode = nil -- "entry" | "order" | "labels"

  for raw_line in contents:gmatch("[^\r\n]+") do
    local line = raw_line
    if not line:match("^%s*#") and trim(line) ~= "" then
      if line:match("^_category%-order:%s*$") then
        current_key = nil
        current_mode = "order"
      elseif line:match("^_category%-labels:%s*$") then
        current_key = nil
        current_mode = "labels"
      else
        local default_cat = line:match("^_default%-category:%s*(.+)%s*$")
        if default_cat then
          result.default_category = unquote(default_cat)
        else
          local top_key = line:match("^(" .. FIELD_PATTERN .. "):%s*$")
          if top_key and not top_key:match("^_") then
            current_key = top_key
            current_mode = "entry"
            result.entries[current_key] = {}
          elseif current_mode == "order" then
            local item = line:match("^%s*%-%s*(.+)%s*$")
            if item then
              table.insert(result.category_order, unquote(item))
            end
          elseif current_mode == "labels" then
            local field, value = line:match("^%s+(" .. FIELD_PATTERN .. "):%s*(.-)%s*$")
            if field and value ~= "" then
              result.category_labels[field] = unquote(value)
            end
          elseif current_mode == "entry" and current_key then
            local field, value = line:match("^%s+(" .. FIELD_PATTERN .. "):%s*(.-)%s*$")
            if field and value ~= "" then
              result.entries[current_key][field] = unquote(value)
            end
          end
        end
      end
    end
  end

  if not result.default_category and #result.category_order > 0 then
    result.default_category = result.category_order[#result.category_order]
  end

  return result
end

local function load_publications_meta()
  local path = resolve_meta_path()
  local file = io.open(path, "r")
  if not file then
    return {
      entries = {},
      category_order = { "highlighted", "additional" },
      category_labels = {
        highlighted = "Selected publications",
        additional = "Additional publications",
      },
      default_category = "additional",
    }
  end
  local contents = file:read("*a")
  file:close()
  return parse_publications_meta(contents)
end

local function entry_for_key(meta, key)
  if not key then
    return nil
  end
  if meta.entries[key] then
    return meta.entries[key]
  end
  local lower = key:lower()
  for entry_key, entry in pairs(meta.entries) do
    if entry_key:lower() == lower then
      return entry
    end
  end
  return nil
end

local function default_category(meta)
  return meta.default_category or "uncategorized"
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
  local entry = entry_for_key(meta, key)
  local extras = {
    category = (entry and entry.category) or default_category(meta),
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

local function category_label(meta, category)
  return meta.category_labels[category]
    or category:gsub("_", " "):gsub("^%l", string.upper)
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

  return pandoc.Div(
    pub_blocks,
    pandoc.Attr(entry.identifier, { "vera-pub" }, { ["data-category"] = extras.category })
  )
end

local function category_rank(meta, category)
  for i, key in ipairs(meta.category_order) do
    if key == category then
      return i
    end
  end
  return (#meta.category_order) + 1
end

local function regroup_by_category(entries, meta)
  if #entries == 0 then
    return entries
  end

  local buckets = {}
  local seen_order = {}

  for _, entry in ipairs(entries) do
    local category = (entry.attributes and entry.attributes["data-category"])
      or default_category(meta)
    if not buckets[category] then
      buckets[category] = {}
      table.insert(seen_order, category)
    end
    table.insert(buckets[category], entry)
  end

  table.sort(seen_order, function(a, b)
    local ra = category_rank(meta, a)
    local rb = category_rank(meta, b)
    if ra == rb then
      return a < b
    end
    return ra < rb
  end)

  -- Single category: keep flat list, no section header needed.
  if #seen_order == 1 then
    return buckets[seen_order[1]]
  end

  local out = {}
  for _, category in ipairs(seen_order) do
    local section_blocks = {
      pandoc.Header(2, { pandoc.Str(category_label(meta, category)) }),
    }
    for _, entry in ipairs(buckets[category]) do
      table.insert(section_blocks, entry)
    end
    table.insert(
      out,
      pandoc.Div(
        section_blocks,
        pandoc.Attr("", { "vera-pub-section" }, { ["data-category"] = category })
      )
    )
  end
  return out
end

local function walk_blocks(blocks, ref_index, meta)
  local out = {}
  for _, block in ipairs(blocks) do
    if block.t == "Div" then
      if block.identifier == "refs" or has_class(block, "references") then
        block.classes:insert("vera-pub-list")
        local transformed = {}
        for _, child in ipairs(block.content) do
          if child.t == "Div" and is_entry(child) then
            table.insert(transformed, transform_entry(child, ref_index, meta))
          else
            table.insert(transformed, child)
          end
        end
        block.content = regroup_by_category(transformed, meta)
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
