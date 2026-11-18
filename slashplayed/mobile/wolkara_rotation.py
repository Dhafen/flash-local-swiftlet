"""Adapt Wolkara's existing spell slots to Tactara's secure manual actions."""

def once(source, before, after):
    if source.count(before) != 1:
        raise ValueError("Unexpected Wolkara source near " + before.splitlines()[0])
    return source.replace(before, after, 1)


def actions(source):
    source = once(source, 'ns.BUILTIN = {', '''ns.BUILTIN = {
    { kind = "tactara", id = "main", name = "One Button Rotation", icon = "Interface\\\\Icons\\\\Ability_Warrior_BattleShout" },
    { kind = "tactara", id = "aoe", name = "AoE Rotation", icon = "Interface\\\\Icons\\\\Ability_Whirlwind" },
    { kind = "tactara", id = "interrupt", name = "Interrupt", icon = "Interface\\\\Icons\\\\Ability_Kick" },''')
    source = once(source, 'function ns.EntryIcon(entry)', '''local TACTARA_TARGETS = {
    main = "TactaraMainButton",
    aoe = "TactaraAoEButton",
    interrupt = "TactaraInterruptButton",
}

function ns.EntryIcon(entry)''')
    source = once(source, 'if entry.kind == "macrotext" then return entry.icon end',
                  'if entry.kind == "macrotext" or entry.kind == "tactara" then return entry.icon end')
    source = once(source, '    button:SetAttribute("macrotext", nil)', '''    button:SetAttribute("macrotext", nil)
    button:SetAttribute("clickbutton", nil)''')
    source = once(source, '    elseif entry.kind == "macrotext" then\n        button:SetAttribute("type", "macro")', '''    elseif entry.kind == "tactara" then
        -- Direct secure game button, not a /click macro or automatic input.
        local name = TACTARA_TARGETS[entry.id]
        local target = name and _G[name]
        button:SetAttribute("type", target and "click" or nil)
        button:SetAttribute("clickbutton", target)
        -- A tap finishes on release, so dragging the wheel does not cast.
        button:SetAttribute("useOnKeyDown", false)
    elseif entry.kind == "macrotext" then
        button:SetAttribute("type", "macro")''')
    # The normal rotating wheel sets useOnKeyDown itself; for a non-rotating
    # slot, preserve the explicit tap-on-release preference only for Tactara.
    source = once(source, '    button.suppressed = nil', '''    button.suppressed = nil
    if button.wolkaraTactara then button:SetAttribute("useOnKeyDown", button.wolkaraTactaraPrevious) end
    button.wolkaraTactara = nil''')
    source = once(source, '        button:SetAttribute("useOnKeyDown", false)', '''        button.wolkaraTactaraPrevious = button:GetAttribute("useOnKeyDown")
        button.wolkaraTactara = true
        button:SetAttribute("useOnKeyDown", false)''')
    source = once(source, '        if entry.kind == "item" then\n            local count', '''        if entry.kind == "tactara" then button.count:SetText(entry.id == "main" and "1-TAP" or entry.id == "aoe" and "AOE" or "INT") end
        if entry.kind == "item" then
            local count''')
    return source


def picker(source):
    return once(source, '''name = entry.kind == "macrotext" and entry.name or nil,
                icon = entry.kind == "macrotext" and entry.icon or nil''', '''name = (entry.kind == "macrotext" or entry.kind == "tactara") and entry.name or nil,
                icon = (entry.kind == "macrotext" or entry.kind == "tactara") and entry.icon or nil''')


def turn(source):
    source = once(source, 'return settings ~= nil and settings.turn == true',
                  'return settings ~= nil and settings.count > 0 and settings.turn == true')
    return once(source, 'button:SetAttribute("useOnKeyDown", nil)', '''local entry = button:GetEntry()
            if entry and entry.kind == "tactara" then
                button:SetAttribute("useOnKeyDown", false)
            else
                button:SetAttribute("useOnKeyDown", nil)
            end''')
