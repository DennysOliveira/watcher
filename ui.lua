local api = require("api")

local function createButton(id, parent, text, x, y, width, height)
    local button = api.Interface:CreateWidget('button', id, parent)
    button:AddAnchor("TOPLEFT", x, y)
    button:SetExtent(width or 80, height or 25)
    button:SetText(text)
    api.Interface:ApplyButtonSkin(button, BUTTON_BASIC.DEFAULT)
    button:Show(true)
    return button
end

local function createLabel(id, parent, text, x, y, fontSize, anchor)
    local label = api.Interface:CreateWidget('label', id, parent)
    label:AddAnchor(anchor or "TOPLEFT", x, y)
    label:SetExtent(255, 20)
    label:SetText(text)
    label.style:SetColor(FONT_COLOR.TITLE[1], FONT_COLOR.TITLE[2], FONT_COLOR.TITLE[3], 1)
    label.style:SetAlign(ALIGN.LEFT)
    label.style:SetFontSize(fontSize or 14)
    label:Show(true)
    return label
end

local function createDropdown(id, parent, x, y, width, height, items)
    local dropdown = api.Interface:CreateComboBox(parent)
    dropdown:SetId(id)
    dropdown:AddAnchor("TOPLEFT", x, y)
    if width and height then
        dropdown:SetExtent(width, height)
    elseif width then
        dropdown:SetExtent(width, 25)
    else
        dropdown:SetExtent(120, 25)
    end
    if items and type(items) == "table" then
        for _, item in ipairs(items) do
            dropdown:AddItem(item)
        end
    end
    dropdown:Show(true)
    return dropdown
end

return {
    createButton = createButton,
    createLabel = createLabel,
    createDropdown = createDropdown
}
