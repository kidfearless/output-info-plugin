# Stripper Dump Parser

Stripper Dump Parser is a mostly extension free alternative to slidybat's [OutputInfo extension](https://github.com/SlidyBat/sm-ext-outputinfo). Stripper Dump Parser processes dump files into single like keyvalues containing information relevant to the entities outputs. From there it's processed and cached into enum struct objects that can be accessed through natives and stocks. As part of being an alternative to OutputInfo, all of the natives provided by the extension are available as stocks.

## Requirements
  - `stripper_dump` functionality either from [Stripper:Source](https://forums.alliedmods.net/showthread.php?t=39439) or [Level KeyValues Stripper](https://github.com/nosoop/SM-LevelKeyValuesStripper)
  - `Sourcemod 1.10` for enum struct support

# ConVars
  - `sm_dump_parser_enabled` - If 0 disables the plugin entirely. Stopping it from creating dumps and caching data.
  - `sm_dump_parser_nocache` - If 0 only parses dump files, does not cache values.

# Enum Structs
  - `Output` - Contains the Output, Target, Input, Parameters, Delay, and Once as members.
  - `Entity` - Contains the Hammer ID, Wait value, Classname, and an ArrayList of it's Outputs.

# Stocks/Natives
  - `bool GetDumpEntity(int index, Entity ent)` - Retrieves a copy of the 'Entity' enum struct for the given index.
  - `bool GetDumpEntity2(int hammerid, Entity ent)` - Retrieves a copy of the 'Entity' enum struct for the given hammer id.
  - `bool IsDumpReady()` - Returns whether or not it's safe to call any stocks/natives

# Forwards
  - `void OnDumpFileReady()` - Fired when either JSON Dump file is found or is fully parsed.
  - `void OnDumpFileProcessed()` - Fired when everything is processed and it's safe to call natives.

### Limitations
  - Cannot retrieve outputs from an entity that are given at run time.
  - Calling the OutputInfo stocks are probably slow and not recommended
  
### ToDo
  - Parse entities from `OnLevelInit` instead of using 3rd party extensions/plugins.
