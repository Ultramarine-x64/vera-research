-- Citeproc + VERA bibliography card styling.

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

local function inlines_to_text(inlines)
  return pandoc.utils.stringify(inlines)
end

local function extract_year(text)
  return text:match("(%d%d%d%d)%.?%s*$") or text:match("(%d%d%d%d)")
end

local function entry_inlines(entry)
  for _, block in ipairs(entry.content) do
    if block.t == "Div" and has_class(block, "csl-right-inline") then
      return block.content
    end
    if block.t == "Para" then
      return block.content
    end
  end
  return {}
end

local function transform_entry(entry)
  local inlines = entry_inlines(entry)
  if #inlines == 0 then
    return entry
  end

  local year = extract_year(inlines_to_text(inlines)) or ""

  return pandoc.Div(
    {
      pandoc.Div(
        { pandoc.Plain({ pandoc.Str(year) }) },
        pandoc.Attr("", { "vera-pub-year" }, {})
      ),
      pandoc.Div(
        { pandoc.Plain(inlines) },
        pandoc.Attr("", { "vera-pub-body" }, {})
      ),
    },
    pandoc.Attr(entry.identifier, { "vera-pub" }, {})
  )
end

local function walk_blocks(blocks)
  local out = {}
  for _, block in ipairs(blocks) do
    if block.t == "Div" then
      if block.identifier == "refs" or has_class(block, "references") then
        block.classes:insert("vera-pub-list")
        block.content = walk_blocks(block.content)
      elseif is_entry(block) then
        block = transform_entry(block)
      else
        block.content = walk_blocks(block.content)
      end
    end
    table.insert(out, block)
  end
  return out
end

function Pandoc(doc)
  doc = pandoc.utils.citeproc(doc)
  doc.blocks = walk_blocks(doc.blocks)
  return doc
end
