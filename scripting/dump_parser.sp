#include <sourcemod>
#include <regex>
#include <dump_parser>

public Plugin myinfo =
{
	name = "Output Dump Parser",
	author = "KiD Fearless",
	description = "Generates and parses stripper dump files.",
	version = "1.5",
	url = "https://steamcommunity.com/id/kidfearless/"
}

#define KEYWORDS_SIZE 6

ArrayList gA_Entites;
StringMap gSM_EntityList;

Handle gH_Forwards_OnFileReady;
Handle gH_Forwards_OnFileProcessed;

ConVar gC_Enabled;
ConVar gC_ParseOnly;

bool gB_Ready;

char gS_StripperPath[PLATFORM_MAX_PATH];
char KEYWORDS[KEYWORDS_SIZE][32] =
{
	"{",
	"}",
	"\"classname\"",
	"wait",
	"hammerid",
	"\"on"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("GetDumpStringMap", Native_GetDumpStringMap);
	CreateNative("GetDumpEntityAsList", Native_GetDumpEntityAsList);
	CreateNative("GetDumpEntityAsArray", Native_GetDumpEntityAsArray);
	CreateNative("GetDumpEntityFromID", Native_GetDumpEntityFromID);
	CreateNative("GetDumpEntityFromIDAsArray", Native_GetDumpEntityFromIDAsArray);
	CreateNative("GetDumpEntities", Native_GetDumpEntities);
	CreateNative("IsDumpReady", Native_IsDumpReady);

	RegPluginLibrary("output_dump_parser");

	return APLRes_Success;
}

public void OnPluginStart()
{
	GetCommandLineParam("+stripper_path", gS_StripperPath, PLATFORM_MAX_PATH, "addons/stripper");

	gH_Forwards_OnFileReady = CreateGlobalForward("OnDumpFileReady", ET_Event);
	gH_Forwards_OnFileProcessed = CreateGlobalForward("OnDumpFileProcessed", ET_Event);

	gC_Enabled = CreateConVar("sm_dump_parser_enabled", "1", "If 0 disables the plugin entirely. Stopping it from creating dumps and caching data.", _, true, 0.0, true, 1.0);
	gC_ParseOnly = CreateConVar("sm_dump_parser_nocache", "0", "If 0 only parses dump files, does not cache values.", _, true, 0.0, true, 1.0);

	gC_Enabled.AddChangeHook(OnPluginToggled);
	gC_ParseOnly.AddChangeHook(OnPluginToggled);

	AutoExecConfig();

	gA_Entites = new ArrayList(sizeof(Entity));
	gSM_EntityList = new StringMap();
}

public void OnPluginToggled(ConVar convar, const char[] oldValue, const char[] newValue)
{
	bool bOld = !!StringToInt(oldValue);
	bool bNew = !!StringToInt(newValue);

	if(bOld && !bNew)
	{
		gB_Ready = false;
		CleanUp();
	}
	else if(!bOld && bNew)
	{
		InitSetup();
	}
}

public void OnConfigsExecuted()
{
	if(gC_Enabled.BoolValue)
	{
		InitSetup();
	}
}

public void OnMapEnd()
{
	gB_Ready = false;
	CleanUp();
}

void InitSetup(bool recursive = false)
{
	char mapName[PLATFORM_MAX_PATH];
	GetCurrentMap(mapName, PLATFORM_MAX_PATH);
	GetMapDisplayName(mapName, mapName, PLATFORM_MAX_PATH);

	char jsonPath[PLATFORM_MAX_PATH];
	FormatEx(jsonPath, PLATFORM_MAX_PATH, "%s/IO", gS_StripperPath);
	// Check for IO folder
	if(!DirExists(jsonPath))
	{
		LOG("DIRECTORY DOESN'T EXIST");
		// Create one if it doesn't exist
		if(!CreateDirectory(jsonPath, 511))
		{
			LogError("JSON PARSER COULD NOT CREATE IO FOLDER");
			return;
		}
		else //we created the folder and know that we haven't parsed any files. time to restart the process
		{
			LOG("CREATING DUMP FILE");
			// If we've gotten to this point twice now, then we haven't been able to successfully create the folder. Time to give up.
			if(recursive)
			{
				LOG("RECURSION LOOP DETECTED");
			}
			else
			{
				LOG("RECURSION TEST... GENERATING DUMP FILE");
				ServerCommand("stripper_dump");
				CreateTimer(1.0, Timer_Delayed_Init);
				return;
			}
		}
	}
	else
	{
		LOG("DIRECTORY EXISTS...CHECKING FOR JSON FILE");
		Format(jsonPath, PLATFORM_MAX_PATH, "%s/%s.JSON", jsonPath, mapName);
		if(!FileExists(jsonPath))
		{
			LOG("JSON FILE DOESN'T EXIST... CHECKING FOR CFG FILES");
			char stripperFile[PLATFORM_MAX_PATH];
			bool found = false;
			for(int i = 9; (found == false); --i)
			{
				// Find the most recent within ten files
				FormatEx(stripperFile, PLATFORM_MAX_PATH, "%s/dumps/%s.000%i.cfg", gS_StripperPath, mapName, i);
				PrintToServer("stripperFile: %s", stripperFile);
				if(FileExists(stripperFile))
				{
					LOG("FOUND FILE");
					found = true;
				}
				if(i == -1)
				{
					LOG("CFG FILE DOESN'T EXIST... GENERATING DUMP FILE");
					// If we've gotten to this point with recursive set to true, then we've already attempted to make a dump. Better give up.
					if(recursive)
					{
						LOG("RECURSIVE LOOP DETECTED...STOPPING EXECUTION THIS MAP");
						return;
					}
					else
					{
						ServerCommand("stripper_dump");
						CreateTimer(1.0, Timer_Delayed_Init);
						return;
					}
				}
			}

			File mapFile = OpenFile(stripperFile, "r");

			char kvPath[PLATFORM_MAX_PATH];
			FormatEx(kvPath, PLATFORM_MAX_PATH, "%s/dumps/%s.kv", gS_StripperPath, mapName);
			File kvFile = OpenFile(kvPath, "a+");

			if(mapFile == null || kvFile == null)
			{
				LogError("ERROR: Could not open mapFile: '%s'", stripperFile);
				return;
			}
			// Big buffer for entities with large amounts of I/O
			char buffer[OUTPUT_SIZE];
			while(!mapFile.EndOfFile())
			{
				if(!mapFile.ReadLine(buffer, OUTPUT_SIZE))
				{
					break;
				}
				char replace[] = "}\n";
				ReplaceString(buffer, OUTPUT_SIZE, "\n", "");
				ReplaceString(buffer, OUTPUT_SIZE, "}", replace);
				// ReplaceString(buffer, OUTPUT_SIZE, "\" \"", "\": \"");
				ReplaceString(buffer, OUTPUT_SIZE, "\e", ";");

				StripLine(buffer);
				kvFile.WriteString(buffer, false);
			}
			delete mapFile;
			kvFile.Seek(0, SEEK_SET);
			char kvPath2[PLATFORM_MAX_PATH];
			FormatEx(kvPath2, PLATFORM_MAX_PATH, "%s2", kvPath);
			File kvFile2 = OpenFile(kvPath2, "a+");
			Regex regIdOnly = new Regex("^{(\"classname\" \"\\S*\")?,? ?(\"hammerid\" \"\\d*\")?,? ?(\"wait\" \"\\d?.?\\d?\")?,? ?}?$");

			while(!kvFile.EndOfFile())
			{
				if(!kvFile.ReadLine(buffer, OUTPUT_SIZE))
				{
					break;
				}
				ReplaceString(buffer, OUTPUT_SIZE, "{}", "");
				// ReplaceString(buffer, OUTPUT_SIZE, "\"\"", "\", \"");
				if(regIdOnly.Match(buffer) > 0)
				{
					char buffer2[OUTPUT_SIZE]
					regIdOnly.GetSubString(0, buffer2, OUTPUT_SIZE);
					ReplaceString(buffer, OUTPUT_SIZE, buffer2, "");
				}

				kvFile2.WriteString(buffer, false);
			}
			delete regIdOnly;
			delete kvFile;
			#if !defined NO_DEL
			DeleteFile(kvPath);
			#endif
			kvFile2.Seek(0, SEEK_SET);
			File JSONOutput = OpenFile(jsonPath, "a+");
			// int counter = 0;

			while(!kvFile2.EndOfFile())
			{
				if(!kvFile2.ReadLine(buffer, OUTPUT_SIZE))
				{
					break;
				}
				FormatOutputString(buffer);
				if(!StrEqual(buffer, "\n"))
				{
					ReplaceString(buffer, OUTPUT_SIZE, "{", "\"0\"{");
					JSONOutput.WriteString(buffer, false);
				}
			}
			delete JSONOutput;
			delete kvFile2;
			DeleteFile(kvPath2);
			Ready(mapName);
		}
		else
		{
			LOG("JSON FILE EXISTS... SCANNING FILE");
			Ready(mapName);
		}
	}
}

void Ready(char mapName[PLATFORM_MAX_PATH])
{
	Call_StartForward(gH_Forwards_OnFileReady);
	Call_Finish();

	if(gA_Entites.Length > 0 || gSM_EntityList.Size > 0)
	{
		CleanUp();
	}

	if(gC_ParseOnly.BoolValue)
	{
		return;
	}


	// Point to the location of the formatted output list
	char path[PLATFORM_MAX_PATH];
	FormatEx(path, PLATFORM_MAX_PATH, "%s/IO/%s.JSON", gS_StripperPath, mapName);
	// If an output list couldn't be found stop the operation

	// Open the file for reading, if an error occurs then log it
	if(!FileExists(path))
	{
		LogError("ERROR: COULD NOT FIND IO JSON FILE: %s", path);
		SetFailState("NO JSON FILE FOUND. UNLOADING PLUGIN");
		return;
	}

	File ioFile = OpenFile(path, "r");

	if(ioFile == null)
	{
		LogError("ERROR: COULD NOT OPEN IO JSON FILE: %s", path);
		return;
	}

	while(!IsEndOfFile(ioFile))
	{
		char buffer[OUTPUT_SIZE];
		// Import a kv file from the line that was read.

		if(!ioFile.ReadLine(buffer, OUTPUT_SIZE))
		{
			break;
		}
		KeyValues kv = new KeyValues("0");
		if(!kv.ImportFromString(buffer))
		{
			LogError("Could not parse kv file: '%s'", buffer);
			continue;
		}
		Entity ent;

		// Grab it's hammer id
		char hammerid[MEMBER_SIZE];
		kv.GetString("hammerid", hammerid, MEMBER_SIZE);
		strcopy(ent.HammerID, MEMBER_SIZE, hammerid);

		char wait[MEMBER_SIZE];
		kv.GetString("wait", wait, MEMBER_SIZE);
		ent.Wait = StringToFloat(wait);

		char classname[MEMBER_SIZE];
		kv.GetString("classname", classname, MEMBER_SIZE);
		strcopy(ent.Classname, MEMBER_SIZE, classname);

		char counter[12];
		strcopy(counter, 12, "0");
		char output[OUTPUT_SIZE];

		// I don't know how this works, but it works, not gonna ask why.
		ent.OutputList = new ArrayList(sizeof(Output));

		// declare an int counter variable. run the HasString function to both check for it's existance and return it's value.
		// Then ONCE it's done increment the variable and format it into the counter.
		for(int i = 0; GetKVString(kv, counter, output, OUTPUT_SIZE); FormatEx(counter, 12, "%i", ++i))
		{
			Output out;
			out.Parse(output);
			ent.OutputList.PushArray(out);
		}

		delete kv;

		// PrintToServer("Original: \n");
		// ent.Dump();
		int index = gA_Entites.PushArray(ent);
		// Entity test;
		// gA_Entites.GetArray(index, test);

		// PrintToServer("Saved: \n");
		// test.Dump();

		// associate the index with the entities hammerid
		gSM_EntityList.SetValue(hammerid, index);
	}

	// HookTriggers();
	delete ioFile;
	gB_Ready = true;
	Call_StartForward(gH_Forwards_OnFileProcessed);
	Call_Finish();
}

void CleanUp()
{
	for(int i = 0; i < gA_Entites.Length; ++i)
	{
		Entity e;
		gA_Entites.GetArray(i, e);
		e.CleanUp();
	}

	gA_Entites.Clear();
	gSM_EntityList.Clear();
}

void StripLine(char[] line, int length = OUTPUT_SIZE)
{
	bool found = false;
	for(int i = 0; i < KEYWORDS_SIZE; ++i)
	{
		if(StringContains(line, KEYWORDS[i]))
		{
			found = true;
			break;
		}
	}
	if(!found)
	{
		strcopy(line, length, "");
	}
}

void FormatOutputString(char[] buffer)
{
	Regex regOutput = new Regex("(\"On\\w*\")");
	int current = 0
	while(regOutput.Match(buffer) > 0)
	{
		char output[256];
		regOutput.GetSubString(1, output, 256);
		char num[12];
		/* Convert the current match number to a string with quotes */
		FormatEx(num, 12, "\"%i\"", current++);// 1 -> 0
		// PrintToConsoleAll(num);
		/* Replace the first occurance of the match with the match number */
		ReplaceStringEx(buffer, OUTPUT_SIZE, output, num);
		/* convert "2" into "2" " so that we can insert the output as the parameter instead */
		Format(num, 12, "%s \"", num);
		/* Strip the quotes from the output "OnStartTouch" - > OnStartTouch */
		StripQuotes(output);
		/* "2" "OnStartTouch; */
		Format(output, 256, "%s%s;", num, output);
		/* "2" " - > "2" "OnStartTouch;*/
		ReplaceStringEx(buffer, OUTPUT_SIZE, num, output);
	}
	delete regOutput;
}

public Action Timer_Delayed_Init(Handle timer)
{
	InitSetup(true);
	return Plugin_Handled;
}

// native StringMap GetDumpStringMap();
public any Native_GetDumpStringMap(Handle plugin, int numParams)
{
	if(!gB_Ready)
	{
		//LogError("Native called before dump file has been processed.");
		return INVALID_HANDLE;
	}
	if(gA_Entites.Length < 1 || gSM_EntityList.Size < 1)
	{
		//LogError("Entity lists are empty.");
		return INVALID_HANDLE;
	}

	return CloneHandle(gSM_EntityList, plugin);
}

// native ArrayList GetDumpEntityAsList(int ent);
public any Native_GetDumpEntityAsList(Handle plugin, int numParams)
{
	if(!gB_Ready)
	{
		//LogError("Native called before dump file has been processed.");
		return INVALID_HANDLE;
	}
	if(gA_Entites.Length < 1 || gSM_EntityList.Size < 1)
	{
		//LogError("Entity lists are empty.");
		return INVALID_HANDLE;
	}

	int index = GetNativeCell(1);
	int hammer = GetHammerFromIndex(index);
	char id[MEMBER_SIZE];
	IntToString(hammer, id, MEMBER_SIZE);

	int position = -1;
	if(!gSM_EntityList.GetValue(id, position))
	{
		//LogError("Could not find entity with with the index '%i', hammmerid '%i'.", index, hammer);
		return INVALID_HANDLE;	
	}

	if(position >= gA_Entites.Length || position < 0)
	{
		//LogError( "List position out of range");
		return INVALID_HANDLE;	
	}

	Entity temp;
	gA_Entites.GetArray(position, temp);
	
	Entity ent;
	CloneEntity(temp, ent);
	ArrayList list = new ArrayList(sizeof(Entity));
	list.PushArray(ent);

	return list;
}

// native bool GetDumpEntityAsArray(int index, any[] entity);
public any Native_GetDumpEntityAsArray(Handle plugin, int numParams)
{
	if(!gB_Ready)
	{
		//LogError("Native called before dump file has been processed.");
		return false;
	}
	if(gA_Entites.Length < 1 || gSM_EntityList.Size < 1)
	{
		//LogError("Entity lists are empty.");
		return false;
	}

	int index = GetNativeCell(1);
	int hammer = GetHammerFromIndex(index);
	char id[MEMBER_SIZE];
	IntToString(hammer, id, MEMBER_SIZE);

	int position = -1;
	if(!gSM_EntityList.GetValue(id, position))
	{
		//LogError("Could not find entity with with the index '%i', hammmerid '%i'.", index, hammer);
		return false;	
	}

	if(position >= gA_Entites.Length || position < 0)
	{
		//LogError( "List position out of range");
		return false;	
	}

	Entity temp;
	gA_Entites.GetArray(position, temp);
	
	Entity ent;
	CloneEntity(temp, ent);
	SetNativeArray(2, ent, sizeof(Entity));

	return true;
}

// native ArrayList GetDumpEntityFromID(int ent);
public any Native_GetDumpEntityFromID(Handle plugin, int numParams)
{
	if(!gB_Ready)
	{
		//LogError("Native called before dump file has been processed.");
		return INVALID_HANDLE;
	}
	if(gA_Entites.Length < 1 || gSM_EntityList.Size < 1)
	{
		//LogError("Entity lists are empty.");
		return INVALID_HANDLE;
	}

	int hammer = GetNativeCell(1);
	char id[MEMBER_SIZE];
	IntToString(hammer, id, MEMBER_SIZE);

	int position = -1;
	if(!gSM_EntityList.GetValue(id, position))
	{
		//LogError("Could not find entity with that index.");
		return INVALID_HANDLE;	
	}

	if(position >= gA_Entites.Length || position < 0)
	{
		//LogError("List position out of range");
		return INVALID_HANDLE;	
	}

	Entity temp;
	gA_Entites.GetArray(position, temp);
	
	Entity ent;
	CloneEntity(temp, ent);
	ArrayList list = new ArrayList(sizeof(Entity));
	list.PushArray(ent);

	return list;
}

// native bool GetDumpEntityFromIDAsArray(int hammerid, any[] entity);
public any Native_GetDumpEntityFromIDAsArray(Handle plugin, int numParams)
{
	if(!gB_Ready)
	{
		//LogError("Native called before dump file has been processed.");
		return false;
	}
	if(gA_Entites.Length < 1 || gSM_EntityList.Size < 1)
	{
		//LogError("Entity lists are empty.");
		return false;
	}

	int hammer = GetNativeCell(1);
	char id[MEMBER_SIZE];
	IntToString(hammer, id, MEMBER_SIZE);

	int position = -1;
	if(!gSM_EntityList.GetValue(id, position))
	{
		//LogError("Could not find entity with that index.");
		return false;	
	}

	if(position >= gA_Entites.Length || position < 0)
	{
		//LogError("List position out of range");
		return false;	
	}

	Entity temp;
	gA_Entites.GetArray(position, temp);
	
	Entity ent;
	CloneEntity(temp, ent);


	return true;
}

// native ArrayList GetDumpEntities();
public any Native_GetDumpEntities(Handle plugin, int numParams)
{
	if(!gB_Ready)
	{
		//LogError("Native called before dump file has been processed.");
		return INVALID_HANDLE;
	}
	if(gA_Entites.Length < 1 || gSM_EntityList.Size < 1)
	{
		//LogError("Entity lists are empty.");
		return INVALID_HANDLE;
	}
	
	ArrayList temp = new ArrayList(sizeof(Entity));

	for(int i = 0; i < gA_Entites.Length; ++i)
	{
		Entity original;
		gA_Entites.GetArray(i, original);

		Entity cloned;
		CloneEntity(original, cloned);

		temp.PushArray(cloned);
	}
	
	return temp;
}

// native bool IsDumpReady();
public any Native_IsDumpReady(Handle plugin, int numParams)
{
	return gB_Ready;
}