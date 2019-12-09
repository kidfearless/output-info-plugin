# Output Info Plugin

Output Info Plugin is a mostly extension free alternative to slidybat's [OutputInfo extension](https://github.com/SlidyBat/sm-ext-outputinfo). Output Info Plugin takes the map entities string from `OnLevelInit` and stores the relevant information in enum structs. The plugin will create it's own implementation of the OutputInfo natives if none can be found. As long as the plugin calling the natives doesn't have OutputInfo as a required extension then Output Info Plugin can handle them.

## Requirements
  - `Sourcemod 1.10` for enum struct support.

# Enum Structs
  - `Output` - Contains the Output, Target, Input, Parameters, Delay, and Once as members.
  - `Entity` - Contains the Hammer ID, Wait value, Classname, and an ArrayList of it's Outputs.

# Natives
  - `bool GetOutputEntity(int index, Entity ent)` - Retrieves a copy of the 'Entity' enum struct for the given index.
  - `bool GetOutputEntities()` - Retrieves a copy of all the cached Entities.
  - `bool AreEntitiesReady()` - Returns whether or not it's safe to call any natives.
  -
  - `int GetOutputCount(int index, const char[] output = "")` - Retrieves the number of outputs that have the given trigger.
  - `bool GetOutputTarget(int index, const char[] output, int num, char[] target, int length = MEMBER_SIZE)` - Retrieves the target at the current index for the given output.
  - `GetOutputTargetInput(int index, const char[] output, int num, char[] input, int length = MEMBER_SIZE)` - Retrieves the input at the current index for the given output.
  - `GetOutputParameter(int index, const char[] output, int num, char[] parameters, int length = MEMBER_SIZE)` - Retrieves the output parameters at the current index for the given output.
  - `float GetOutputDelay(int index, const char[] output, int num)` - Retrieves the output delay at the current index for the given output.
  -
  - `int GetOutputActionCount(int index, const char[] output = "")` - Retrieves the number of outputs that have the given trigger.
  - `bool GetOutputActionTarget(int index, const char[] output, int num, char[] target, int length = MEMBER_SIZE)` - Retrieves the target at the current index for the given output.
  - `GetOutputActionTargetInput(int index, const char[] output, int num, char[] input, int length = MEMBER_SIZE)` - Retrieves the input at the current index for the given output.
  - `GetOutputActionParameter(int index, const char[] output, int num, char[] parameters, int length = MEMBER_SIZE)` - Retrieves the output parameters at the current index for the given output.
  - `float GetOutputActionDelay(int index, const char[] output, int num)` - Retrieves the output delay at the current index for the given output.

# Forwards
  - `void OnEntitiesReady()` - Fired when everything is processed and it's safe to call natives.

### Limitations
  - Cannot retrieve outputs from an entity that are given at run time.
