#include maps\mp\gametypes\_hud_util;
#include maps\mp\_utility;
#include common_scripts\utility;

main()
{
    printLn("^5[MAPVOTE] mapvotet4 loaded!");

    SetDvarIfNotInitialized("mapvote_enable", true);

    if (GetDvarInt("mapvote_enable"))
    {
        iprintln("[MAPVOTE] mapvote_enable is enabled! Initializing...");
        initMv();
        level thread ListenForEndVote();
    }
}

initMv()
{
    if (GetDvarInt("mapvote_enable"))
    {
        InitMapvote();
    }
}

InitMapvote()
{
    InitDvars();
    InitVariables();

    if (GetDvarInt("mapvote_debug"))
    {
        Print("[MAPVOTE] Debug mode is ON");
        wait 3;
        level thread StartVote();
    }
}

InitDvars()
{
    SetDvarIfNotInitialized("mapvote_debug", false);
    SetDvarIfNotInitialized("mapvote_maps", "Castle:Makin:Roundhouse:Asylum:Airfield:Seelow:Dome:Downfall:Hangar:Cliffside:Courtyard:Upheaval:Outskirts:Nightfire:Station:Knee Deep:Makin Day:Banzai:Corrosion:Sub Pens:Battery:Breach:Revolution");

    SetDvarIfNotInitialized("mapvote_limits_maps", 6); // only 4 maps at once
    SetDvarIfNotInitialized("mapvote_modes", "Search & Destroy,sd");
    SetDvarIfNotInitialized("mapvote_limits_modes", 0);

    SetDvarIfNotInitialized("mapvote_sounds_menu_enabled", 1);
    SetDvarIfNotInitialized("mapvote_sounds_timer_enabled", 1);
    SetDvarIfNotInitialized("mapvote_limits_max", 11);
    SetDvarIfNotInitialized("mapvote_colors_selected", "green");
    SetDvarIfNotInitialized("mapvote_colors_unselected", "white");
    SetDvarIfNotInitialized("mapvote_colors_timer", "yellow");
    SetDvarIfNotInitialized("mapvote_colors_timer_low", "red");
    SetDvarIfNotInitialized("mapvote_colors_help_text", "white");
    SetDvarIfNotInitialized("mapvote_colors_help_accent", "yellow");
    SetDvarIfNotInitialized("mapvote_colors_help_accent_mode", "standard");
    SetDvarIfNotInitialized("mapvote_vote_time", 20);
    SetDvarIfNotInitialized("mapvote_horizontal_spacing", 75);
    SetDvarIfNotInitialized("mapvote_display_wait_time", 4);
}

InitVariables()
{
    mapsArray = StrTok(GetDvar("mapvote_maps"), ":");

    voteLimits = [];
    if (GetDvarInt("mapvote_limits_maps") == 0)
        voteLimits["maps"] = mapsArray.size;
    else
        voteLimits["maps"] = GetDvarInt("mapvote_limits_maps");

    voteLimits["modes"] = 0; // we ignore modes

    level.mapvote = [];
    level.mapvote["limit"] = [];
    level.mapvote["limit"]["maps"]  = voteLimits["maps"];
    level.mapvote["limit"]["modes"] = 0;

    level.mapvote["maps"] = [];
    level.mapvote["vote"] = [];
    level.mapvote["hud"]  = [];

    SetMapvoteData("map");

    // Initialize vote counters
    level.mapvote["vote"]["maps"] = [];
    for (i = 0; i < level.mapvote["maps"]["by_index"].size; i++)
    {
        level.mapvote["vote"]["maps"][i] = 0;
    }
    // Store HUD references
    level.mapvote["hud"]["maps"] = [];

    // Initialize voters tracking
    level.mapvote["voters"] = [];
    level.mapvote["voters"]["maps"] = [];
    for (i = 0; i < level.mapvote["maps"]["by_index"].size; i++)
    {
        level.mapvote["voters"]["maps"][i] = [];
    }
}

StartVote()
{
    if (isDefined(level.mapvote_running) && level.mapvote_running)
    {
        printLn("^1[MAPVOTE ERROR] StartVote() called but already running!");
        return;
    }
    level.mapvote_running = true;
    level endon("mapvote_vote_end");

    thread CreateVoteMenu();
    thread CreateVoteTimer();

    // Set up HUD and input for each real player
    for (i = 0; i < level.players.size; i++)
    {
        player = level.players[i];
        if (isDefined(player.pers["isBot"]) && player.pers["isBot"])
            continue;

        player thread SetupPerPlayerHUD();
        player thread ListenForVoteInputs();
        player thread OnPlayerDisconnect();
    }
}

// ### CreateVoteMenu()
// Creates the server-side HUD for vote counters, player names, title, and help text.
CreateVoteMenu()
{
    // Create black background HUD
    level.mapvote_backgroundhud = newHudElem();
    level.mapvote_backgroundhud.horzAlign = "center";
    level.mapvote_backgroundhud.vertAlign = "center";
    level.mapvote_backgroundhud.x = -430;
    level.mapvote_backgroundhud.y = -180;
    level.mapvote_backgroundhud setShader("black", 920, 720);  // Size
    level.mapvote_backgroundhud.sort = 0;                     // Draw behind other HUDs
    level.mapvote_backgroundhud.alpha = 1;                    // Fully opaque
    level.mapvote_backgroundhud.hideWhenInMenu = true;        // Hide when menu is open

    // Centered title near top
    level.mapvote_titlehud = CreateHudText(
        "^7VOTE FOR THE NEXT MAP!",
        "objective",
        3,
        "CENTER",
        "TOP",
        0,
        80,
        true
    );
    level.mapvote_titlehud.sort = 2;  // Ensure it’s above the background

    numMaps = level.mapvote["maps"]["by_index"].size;

    // Numeric HUD on the right
    baseY   = -40;
    spacing = 20;
    offsetY = baseY;

// Create white lines between map names
    level.mapvote_lines = [];
    for (m = 0; m < numMaps - 1; m++)  // numMaps - 1 lines between maps
    {
        lineY = baseY + (m * spacing) + (spacing / 2);  // Position between map names
        lineHud = newHudElem();
        lineHud.horzAlign = "center";
        lineHud.vertAlign = "middle";
        lineHud.x = -300;
        lineHud.y = lineY;
        lineHud setShader("white", 600, 2);  // Width matches black box, height is 2 pixels
        lineHud.sort = 1;                  // Above black box but below text
        lineHud.alpha = 1;
        lineHud.hideWhenInMenu = true;
        level.mapvote_lines[m] = lineHud;
    }
	
    for (m = 0; m < numMaps; m++)
    {
        mapVotesHud = CreateHudText(
            "0",
            "objective",
            2,
            "LEFT",
            "CENTER",
            -50,
            offsetY,
            true,
            0
        );
        mapVotesHud.sort = 2;  // Ensure it’s above the background
        level.mapvote["hud"]["maps"][m] = mapVotesHud;
        offsetY += spacing;
    }

    // HUD for player names
    level.mapvote["hud"]["names"] = [];
    for (m = 0; m < numMaps; m++)
    {
        namesHud = CreateHudText(
            "",
            "small",
            1,
            "LEFT",
            "CENTER",
            0,
            baseY + m * spacing,
            true
        );
        namesHud.sort = 2;  // Ensure it’s above the background
        level.mapvote["hud"]["names"][m] = namesHud;
    }

    // Help text
    level.mapvote_helphud = CreateHudText(
       "^7Press [{+attack}] to go Down / [{+frag}] to go Up / X or [{+activate}] to Vote",
        "objective",
        2,
        "CENTER",
        "CENTER",
        0,
        160,
        true
    );
    level.mapvote_helphud.sort = 2;  // Ensure it’s above the background
}

// ### CreateVoteTimer()
// Manages the voting timer and sound effects.
CreateVoteTimer()
{
    soundFX = spawn("script_origin", (0,0,0));
    soundFX hide();

    time = GetDvarInt("mapvote_vote_time");

    level.mapvote["timerhud"] = CreateTimer(
        time,
        "Vote ends in: ",
        "objective",
        2,
        "CENTER",
        "CENTER",
        0,
        -210
    );
    level.mapvote["timerhud"].color = "white";
	level.mapvote["timerhud"].sort = 2;

    for (i = time; i > 0; i--)
    {
        if (i <= 5)
        {
            level.mapvote["timerhud"].color = GetGscColor(GetDvar("mapvote_colors_timer_low"));
            if (GetDvarInt("mapvote_sounds_timer_enabled"))
            {
                soundFX playSound("ui_mp_timer_countdown");
            }
        }
        wait(1);
    }

    level notify("mapvote_vote_end");
    wait(0.1);

    DestroyAllVoteHUDs();
}

// ### DestroyAllVoteHUDs()
// Cleans up all HUD elements when voting ends.
DestroyAllVoteHUDs()
{
    // 1) Destroy the timer HUD
    if (IsDefined(level.mapvote["timerhud"]))
    {
        level.mapvote["timerhud"] Destroy();
        level.mapvote["timerhud"] = undefined;
    }

    // 2) Destroy the numeric HUDs for maps
    if (IsDefined(level.mapvote["hud"]["maps"]))
    {
        hudKeys = GetArrayKeys(level.mapvote["hud"]["maps"]);
        for (k = 0; k < hudKeys.size; k++)
        {
            idx = hudKeys[k];
            if (IsDefined(level.mapvote["hud"]["maps"][idx]))
            {
                level.mapvote["hud"]["maps"][idx] Destroy();
                level.mapvote["hud"]["maps"][idx] = undefined;
            }
        }
    }

    // 3) Destroy the HUD elements for player names
    if (IsDefined(level.mapvote["hud"]["names"]))
    {
        nameKeys = GetArrayKeys(level.mapvote["hud"]["names"]);
        for (k = 0; k < nameKeys.size; k++)
        {
            idx = nameKeys[k];
            if (IsDefined(level.mapvote["hud"]["names"][idx]))
            {
                level.mapvote["hud"]["names"][idx] Destroy();
                level.mapvote["hud"]["names"][idx] = undefined;
            }
        }
        level.mapvote["hud"]["names"] = undefined;  // Clear the array reference
    }

    // 4) Destroy the white lines HUD
    if (IsDefined(level.mapvote_lines))
    {
        lineKeys = GetArrayKeys(level.mapvote_lines);
        for (k = 0; k < lineKeys.size; k++)
        {
            idx = lineKeys[k];
            if (IsDefined(level.mapvote_lines[idx]))
            {
                level.mapvote_lines[idx] Destroy();
                level.mapvote_lines[idx] = undefined;
            }
        }
        level.mapvote_lines = undefined;
    }

    // 5) Destroy the title HUD
    if (IsDefined(level.mapvote_titlehud))
    {
        level.mapvote_titlehud Destroy();
        level.mapvote_titlehud = undefined;
    }

    // 6) Destroy the help HUD
    if (IsDefined(level.mapvote_helphud))
    {
        level.mapvote_helphud Destroy();
        level.mapvote_helphud = undefined;
    }

    // 7) Destroy each player's multiline HUD
    players = level.players;
    for (p = 0; p < players.size; p++)
    {
        if (IsDefined(players[p].mapvote_multiHud))
        {
            players[p].mapvote_multiHud Destroy();
            players[p].mapvote_multiHud = undefined;
        }
    }
}
// ### ListenForEndVote()
// Determines the winning map and rotates to it.
ListenForEndVote()
{
    level waittill("mapvote_vote_end");

    mapsArrayKeys = GetArrayKeys(level.mapvote["vote"]["maps"]);
    maxVotes = 0;
    for (i = 0; i < mapsArrayKeys.size; i++)
    {
        idx   = mapsArrayKeys[i];
        votes = level.mapvote["vote"]["maps"][idx];
        if (votes > maxVotes)
        {
            maxVotes = votes;
        }
    }

    tieMaps = [];
    for (i = 0; i < mapsArrayKeys.size; i++)
    {
        idx   = mapsArrayKeys[i];
        votes = level.mapvote["vote"]["maps"][idx];
        if (votes == maxVotes)
        {
            tieMaps = AddElementToArray(tieMaps, idx);
        }
    }

    if (maxVotes == 0)
    {
        mostVotedMapIndex = GetRandomElementInArray(mapsArrayKeys);
    }
    else
    {
        if (tieMaps.size > 1)
            chosenIdx = tieMaps[randomInt(tieMaps.size)];
        else
            chosenIdx = tieMaps[0];

        mostVotedMapIndex = chosenIdx;
    }

    mapName = level.mapvote["maps"]["by_index"][mostVotedMapIndex];
    wait 0.5;

    level.mapvote_winnerhud = CreateHudText(
        "NEXT MAP: " + mapName + "!",
        "objective",
        3,
        "CENTER",
        "CENTER",
        0,
        20,
        true
    );
	level.mapvote_winnerhud.sort = 2;

    wait 4;

    if (IsDefined(level.mapvote_winnerhud))
    {
        level.mapvote_winnerhud Destroy();
        level.mapvote_winnerhud = undefined;
    }

    // Destroy the background HUD after winner display
    if (IsDefined(level.mapvote_backgroundhud))
    {
        level.mapvote_backgroundhud Destroy();
        level.mapvote_backgroundhud = undefined;
    }

    RotateToChoice(mapName);
}

// ### RotateToChoice(mapName)
// Rotates the server to the selected map.
RotateToChoice(mapName)
{
    actualMapName = GetMapCodeName(mapName);
    setDvar("sv_mapRotation", "map " + actualMapName);
    setDvar("sv_mapRotationCurrent", "");
    wait(0.05);
}

// ### SetupPerPlayerHUD()
// Sets up the per-player map selection HUD.
SetupPerPlayerHUD()
{
    self.mapvote_multiHud = self CreateFontString("objective", 1.7);
    self.mapvote_multiHud SetPoint("CENTER","CENTER", -200, -41);
    self.mapvote_multiHud.hidewheninmenu = true;
    self.mapvote_multiHud.glowalpha      = 0;
	self.mapvote_multiHud.sort = 2;

    self.mapvote_hoveredMapIndex  = 0;
    self.mapvote_selectedMapIndex = -1;

    self UpdatePlayerMapListDisplay();
}

// ### UpdatePlayerMapListDisplay()
// Updates the player's map list with highlighting.
UpdatePlayerMapListDisplay()
{
    if (!isDefined(self.mapvote_multiHud))
        return;

    newText = "";
    numMaps = level.mapvote["maps"]["by_index"].size;
    for (m = 0; m < numMaps; m++)
    {
        mapName = level.mapvote["maps"]["by_index"][m];
        if (m == self.mapvote_hoveredMapIndex)
            newText += "^2" + (m+1) + ".   " + mapName + "\n";
        else
            newText += "^7" + (m+1) + ".   " + mapName + "\n";
    }

    self.mapvote_multiHud setText(newText);
}

// ### ListenForVoteInputs()
// Listens for player input to navigate and vote.
ListenForVoteInputs()
{
    self endon("disconnect");

    while (true)
    {
        if (self AttackButtonPressed())
        {
            self ProcessMapInput("mapvote_down");
            wait 0.2;
        }
        else if (self FragButtonPressed())
        {
            self ProcessMapInput("mapvote_up");
            wait 0.2;
        }
        else if (self UseButtonPressed())
        {
            self ProcessMapInput("mapvote_select");
            wait 0.2;
        }
        wait(0.05);
    }
}

// ### ProcessMapInput(action)
// Handles player navigation and voting actions.
ProcessMapInput(action)
{
    if (action == "mapvote_down")
    {
        if (self.mapvote_hoveredMapIndex < (level.mapvote["maps"]["by_index"].size - 1))
        {
            self.mapvote_hoveredMapIndex++;
            self playLocalSound("uin_timer_wager_beep");
            self UpdatePlayerMapListDisplay();
        }
    }
    else if (action == "mapvote_up")
    {
        if (self.mapvote_hoveredMapIndex > 0)
        {
            self.mapvote_hoveredMapIndex--;
            self playLocalSound("uin_timer_wager_beep");
            self UpdatePlayerMapListDisplay();
        }
    }
    else if (action == "mapvote_select")
    {
        if (self.mapvote_selectedMapIndex == self.mapvote_hoveredMapIndex)
            return;

        if (self.mapvote_selectedMapIndex != -1)
        {
            prevMapIndex = self.mapvote_selectedMapIndex;
            level.mapvote["vote"]["maps"][prevMapIndex]--;
            if (IsDefined(level.mapvote["hud"]["maps"][prevMapIndex]))
            {
                level.mapvote["hud"]["maps"][prevMapIndex]
                    SetValue(level.mapvote["vote"]["maps"][prevMapIndex]);
            }
            level.mapvote["voters"]["maps"][prevMapIndex] = ArrayRemove(level.mapvote["voters"]["maps"][prevMapIndex], self);
            UpdateNamesHud(prevMapIndex);
        }

        newMapIndex = self.mapvote_hoveredMapIndex;
        level.mapvote["vote"]["maps"][newMapIndex]++;
        if (IsDefined(level.mapvote["hud"]["maps"][newMapIndex]))
        {
            level.mapvote["hud"]["maps"][newMapIndex]
                SetValue(level.mapvote["vote"]["maps"][newMapIndex]);
        }
        level.mapvote["voters"]["maps"][newMapIndex] = AddElementToArray(level.mapvote["voters"]["maps"][newMapIndex], self);
        UpdateNamesHud(newMapIndex);

        self.mapvote_selectedMapIndex = newMapIndex;
        self playLocalSound("fly_equipment_pickup_plr");
    }
}

// ### OnPlayerDisconnect()
// Cleans up when a player disconnects.
OnPlayerDisconnect()
{
    self waittill("disconnect");

    if (self.mapvote_selectedMapIndex != -1)
    {
        mapIndex = self.mapvote_selectedMapIndex;
        level.mapvote["vote"]["maps"][mapIndex]--;
        if (IsDefined(level.mapvote["hud"]["maps"][mapIndex]))
        {
            level.mapvote["hud"]["maps"][mapIndex]
                SetValue(level.mapvote["vote"]["maps"][mapIndex]);
        }
        level.mapvote["voters"]["maps"][mapIndex] = ArrayRemove(level.mapvote["voters"]["maps"][mapIndex], self);
        UpdateNamesHud(mapIndex);
    }

    if (IsDefined(self.mapvote_multiHud))
    {
        self.mapvote_multiHud Destroy();
        self.mapvote_multiHud = undefined;
    }
}

// ### SetMapvoteData("map")
// Sets up the map data for voting.
SetMapvoteData(type)
{
    if (type != "map") return;

    limit = level.mapvote["limit"]["maps"];
    availableElements = StrTok(GetDvar("mapvote_maps"), ":");
    if (availableElements.size < limit)
    {
        limit = availableElements.size;
    }
    level.mapvote["maps"]["by_index"] = GetRandomUniqueElementsInArray(availableElements, limit);
}

// ### UpdateNamesHud(mapIndex)
// Updates the HUD with player names for a specific map.
UpdateNamesHud(mapIndex)
{
    voters = level.mapvote["voters"]["maps"][mapIndex];
    namesText = "";
    for (i = 0; i < voters.size; i++)
    {
        if (i > 0) namesText += ", ";
        namesText += voters[i].name;
    }
    if (IsDefined(level.mapvote["hud"]["names"][mapIndex]))
    {
        level.mapvote["hud"]["names"][mapIndex] setText(namesText);
    }
}

// ### Basic Helpers
SetDvarIfNotInitialized(dvar, value)
{
    if (!IsInitialized(dvar))
    {
        SetDvar(dvar, value);
    }
}

IsInitialized(dvar)
{
    result = GetDvar(dvar);
    return (result != "");
}

GetRandomElementInArray(array)
{
    return array[ GetArrayKeys(array)[ randomint(array.size) ] ];
}

GetRandomUniqueElementsInArray(array, limit)
{
    finalElements = [];
    for (i = 0; i < limit; i++)
    {
        findElement = true;
        while (findElement)
        {
            randomElement = GetRandomElementInArray(array);
            if (!ArrayContainsValue(finalElements, randomElement))
            {
                finalElements = AddElementToArray(finalElements, randomElement);
                findElement   = false;
            }
        }
    }
    return finalElements;
}

ArrayContainsValue(array, valueToFind)
{
    for (i = 0; i < array.size; i++)
    {
        if (array[i] == valueToFind)
        {
            return true;
        }
    }
    return false;
}

AddElementToArray(array, element)
{
    array[array.size] = element;
    return array;
}

ArrayRemove(array, element)
{
    newArray = [];
    for (i = 0; i < array.size; i++)
    {
        if (array[i] != element)
        {
            newArray[newArray.size] = array[i];
        }
    }
    return newArray;
}

GetMapCodeName(friendlyName)
{
    lowerName = ToLower(friendlyName);

    switch (lowerName)
    {
        case "airfield":    return "mp_airfield";
        case "asylum":      return "mp_asylum";
        case "banzai":      return "mp_kwai";
        case "battery":     return "mp_drum";
        case "breach":      return "mp_bgate";
        case "castle":      return "mp_castle";
        case "cliffside":   return "mp_shrine";
        case "corrosion":   return "mp_stalingrad";
        case "courtyard":   return "mp_courtyard";
        case "dome":        return "mp_dome";
        case "downfall":    return "mp_downfall";
        case "hangar":      return "mp_hangar";
        case "knee deep":   return "mp_kneedeep";
        case "makin":       return "mp_makin";
        case "makin day":   return "mp_makin_day";
        case "nightfire":   return "mp_nachtfeuer";
        case "outskirts":   return "mp_outskirts";
        case "revolution":  return "mp_vodka";
        case "seelow":      return "mp_seelow";
        case "station":     return "mp_subway";
        case "sub pens":    return "mp_docks";
        case "upheaval":    return "mp_suburban";
        default:
            printLn("Unknown map name: " + friendlyName);
            return "mp_airfield";  // Default to a valid map code
    }
}

// ### HUD Creation Helpers
CreateHudText(text, font, fontScale, relativeToX, relativeToY, relativeX, relativeY, isServer, value)
{
    hudText = undefined;
    if (isDefined(isServer) && isServer)
    {
        hudText = CreateServerFontString(font, fontScale);
    }
    else
    {
        hudText = CreateFontString(font, fontScale);
    }

    if (IsDefined(value))
    {
        hudText.label = text;
        hudText SetValue(value);
    }
    else
    {
        hudText setText(text);
    }
    hudText SetPoint(relativeToX, relativeToY, relativeX, relativeY);

    hudText.hidewheninmenu = true;
    hudText.glowalpha      = 0;

    return hudText;
}

CreateTimer(time, label, font, fontScale, relativeToX, relativeToY, relativeX, relativeY)
{
    timer = createServerTimer(font, fontScale);
    timer setPoint(relativeToX, relativeToY, relativeX, relativeY);

    timer.label          = label;
    timer.hidewheninmenu = true;
    timer.glowalpha      = 0;

    timer setTimer(time);
    return timer;
}

GetGscColor(colorName)
{
    switch (colorName)
    {
        case "red":    return (1, 0, 0.059);
        case "green":  return (0.549, 0.882, 0.043);
        case "yellow": return (1, 0.725, 0);
        case "blue":   return (0, 0.553, 0.973);
        case "cyan":   return (0, 0.847, 0.922);
        case "purple": return (0.427, 0.263, 0.651);
        case "white":  return (1, 1, 1);
        case "grey":
        case "gray":   return (0.137, 0.137, 0.137);
        case "black":  return (0, 0, 0);
    }
    return (1,1,1);
}
