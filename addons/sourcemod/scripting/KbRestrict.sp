#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <multicolors>
#include <clientprefs>
#include <KbRestrict>

#define KB_Tag "{deeppink}[Kb-Restrict]{indianred}"

int g_iClientTargets[MAXPLAYERS + 1] = { -1, ... };
int g_iClientTargetsLength[MAXPLAYERS + 1] = { -1, ... };

KeyValues Kv;

ArrayList g_aSteamIDs;

bool g_bKnifeModeEnabled;
bool g_bIsClientRestricted[MAXPLAYERS + 1];
bool g_bIsClientTypingReason[MAXPLAYERS + 1] = { false, ... };

Handle g_hKbRestrictExpireTime[MAXPLAYERS + 1] = {null, ...};

char sPath[PLATFORM_MAX_PATH];

ConVar g_cvDefaultLength;
ConVar g_cvAddBanLength;

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------

public Plugin myinfo = 
{
	name = "Kb-Restrict",
	author = "Dolly, .Rushaway",
	description = "Block knife damage of the knife banned player",
	version = "2.4",
	url = "https://nide.gg"
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------

public void OnPluginStart()
{
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/kbrestrict/userslist.cfg");

	LoadTranslations("KbRestrict.phrases");
	LoadTranslations("common.phrases");

	RegConsoleCmd("sm_kstatus", Command_CheckKbStatus);
	RegConsoleCmd("sm_kbanstatus", Command_CheckKbStatus);
	RegAdminCmd("sm_kban", Command_KbRestrict, ADMFLAG_BAN);
	RegAdminCmd("sm_kunban", Command_KbUnRestrict, ADMFLAG_BAN);
	RegAdminCmd("sm_koban", Command_OfflineKbRestrict, ADMFLAG_BAN);
	
	g_cvDefaultLength = CreateConVar("sm_kbrestrict_length", "30", "Default length when no length is specified");
	g_cvAddBanLength = CreateConVar("sm_kbrestrict_addban_length", "10080", "The Maximume length for offline KbRestrict command");

	AutoExecConfig(true);

	if(!FileExists(sPath))
		SetFailState("File %s is missing", sPath);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			OnClientPutInServer(i);
			if(IsClientAuthorized(i))
				OnClientPostAdminCheck(i);
		}
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnAllPluginsLoaded()
{
	g_bKnifeModeEnabled = LibraryExists("KnifeMode");
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnMapStart()
{
	g_aSteamIDs = new ArrayList(ByteCountToCells(32));
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnClientDisconnect(int client)
{
	g_bIsClientRestricted[client] = false;
	g_bIsClientTypingReason[client] = false;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnClientPostAdminCheck(int client)
{
	ApplyRestrict(client);
}

//----------------------------------------------------------------------------------------------------
// Purpose :
//----------------------------------------------------------------------------------------------------
stock void CreateKv()
{
	Kv = new KeyValues("KbRestrict");
	Kv.ImportFromFile(sPath);
}

//----------------------------------------------------------------------------------------------------
// Purpose :
//----------------------------------------------------------------------------------------------------
stock void AddPlayerToCFG(const char[] sSteamID, const char[] AdminSteamID = "", const char[] sName, const char[] sAdminName, const char[] reason, const char[] date, const char[] sCurrentMap, int time)
{
	CreateKv();

	Kv.JumpToKey(sSteamID, true);
	Kv.SetString("Name", sName);
	Kv.SetString("Admin Name", sAdminName);
	Kv.SetString("AdminSteamID", AdminSteamID);
	Kv.SetString("Reason", reason);
	if(time <= 0)
		Kv.SetString("LengthEx", "Permanent");
	else if(time >= 1)
		Kv.SetNum("Length", time);
	
	Kv.SetString("Date", date);
	Kv.SetNum("TimeStamp", GetTime());
	Kv.SetString("Map", sCurrentMap);
	Kv.Rewind();
	Kv.ExportToFile(sPath);
	
	delete Kv;
}

//----------------------------------------------------------------------------------------------------
// Purpose :
//----------------------------------------------------------------------------------------------------
stock void DeletePlayerFromCFG(const char[] sSteamID)
{
	CreateKv();
	if(Kv.JumpToKey(sSteamID))
	{
		Kv.DeleteThis();
		Kv.Rewind();
		Kv.ExportToFile(sPath);
	}
	
	delete Kv;
}

//----------------------------------------------------------------------------------------------------
// Purpose :
//----------------------------------------------------------------------------------------------------
public Action KbRestrict_ExpireTimerOnline(Handle timer, DataPack datapack)
{
	char SteamID[32];
	datapack.Reset();
	int client = datapack.ReadCell();
	datapack.ReadString(SteamID, sizeof(SteamID));
	
	if(IsValidClient(client))
	{
		g_bIsClientRestricted[client] = false;
		g_hKbRestrictExpireTime[client] = null;
		DeletePlayerFromCFG(SteamID);
		CPrintToChatAll("%s {white}%t {green}%t {white}%N \n%s %t: %t.", KB_Tag, "Console", "Unrestricted", client, "Reason", "Expires", KB_Tag);
	}
	
	return Plugin_Continue;
}

//----------------------------------------------------------------------------------------------------
// Purpose :
//----------------------------------------------------------------------------------------------------
stock void CheckPlayerExpireTime(int lefttime, char[] TimeLeft, int maxlength)
{
	if(lefttime > -1)
	{
		if(lefttime < 60) // 60 secs
			FormatEx(TimeLeft, maxlength, "%02i %t", lefttime, "Seconds");
		else if(lefttime > 3600 && lefttime <= 3660) // 1 Hour
			FormatEx(TimeLeft, maxlength, "%i %t %02i %t", lefttime / 3600, "Hour", (lefttime / 60) % 60, "Minutes");
		else if(lefttime > 3660 && lefttime < 86400) // 2 Hours or more
			FormatEx(TimeLeft, maxlength, "%i %t %02i %t", lefttime / 3600, "Hours", (lefttime / 60) % 60, "Minutes");
		else if(lefttime > 86400 && lefttime <= 172800) // 1 Day
			FormatEx(TimeLeft, maxlength, "%i %t %02i %t", lefttime / 86400, "Day", (lefttime / 3600) % 24, "Hours");
		else if(lefttime > 172800) // 2 Days or more
			FormatEx(TimeLeft, maxlength, "%i %t %02i %t", lefttime / 86400, "Days", (lefttime / 3600) % 24, "Hours");
		else // Less than 1 Hour
			FormatEx(TimeLeft, maxlength, "%i %t %02i %t", lefttime / 60, "Minutes", lefttime % 60, "Seconds");
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose :
//----------------------------------------------------------------------------------------------------
stock int GetCurrent_KbRestrict_Players()
{
	int count = 0;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && g_bIsClientRestricted[i])
			count++;
	}
	
	return count;
}

//----------------------------------------------------------------------------------------------------
// Purpose :
//----------------------------------------------------------------------------------------------------
stock int GetPlayerFromSteamID(const char[] sSteamID)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && IsClientAuthorized(i))
		{
			char SteamID[32];
			GetClientAuthId(i, AuthId_Steam2, SteamID, sizeof(SteamID));
			if(StrEqual(sSteamID, SteamID))
				return i;
		}
	}
	
	return -1;
}

//----------------------------------------------------------------------------------------------------
// Purpose :
//----------------------------------------------------------------------------------------------------
stock bool CheckKbRestrictAuthor(int client, const char[] buffer, const char[] sSteamID)
{
	if(CheckCommandAccess(client, "sm_koban", ADMFLAG_RCON, true))
		return true;
	
	char AdminSteamID[32];
	
	CreateKv();
	if(Kv.JumpToKey(buffer))
	{
		Kv.GetString("AdminSteamID", AdminSteamID, sizeof(AdminSteamID));
		if(StrEqual(sSteamID, AdminSteamID))
			return true;
	}
	delete Kv;
	
	return false;
}

//----------------------------------------------------------------------------------------------------
// Purpose :
//----------------------------------------------------------------------------------------------------
stock bool IsSteamIDInGame(const char[] sSteamID)
{
	g_aSteamIDs.Clear();
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && IsClientAuthorized(i))
		{
			char SteamID[32];
			GetClientAuthId(i, AuthId_Steam2, SteamID, sizeof(SteamID));
			g_aSteamIDs.PushString(SteamID);
		}
	}
	
	if((g_aSteamIDs.FindString(sSteamID) == -1))
		return false;
	
	return true;
}

//----------------------------------------------------------------------------------------------------
// Purpose :
//----------------------------------------------------------------------------------------------------
stock int GetAdminOwn_KbRestrict(int client, const char[] sSteamID)
{
	int count = 0;
	
	CreateKv();
	if(Kv.GotoFirstSubKey())
	{
		do
		{
			char AdminSteamID[32];
			Kv.GetString("AdminSteamID", AdminSteamID, sizeof(AdminSteamID));
			if(StrEqual(sSteamID, AdminSteamID))
			{
				count++;
			}
		}
		while(Kv.GotoNextKey());
	}
	delete Kv;
	
	return count;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
stock void ApplyRestrict(int client)
{
	if(IsValidClient(client))
	{
		char SteamID[32];
		GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID));
		CreateKv();
		if(Kv.JumpToKey(SteamID))
		{
			char sName[MAX_NAME_LENGTH];
			Kv.GetString("Name", sName, sizeof(sName));
			if(StrEqual(sName, "UnKnown"))
			{
				char PlayerName[MAX_NAME_LENGTH];
				GetClientName(client, PlayerName, sizeof(PlayerName));
				Kv.SetString("Name", PlayerName);
				Kv.Rewind();
				Kv.ExportToFile(sPath);
			}
			
			if(Kv.GetNum("Length") != 0)
			{
				int length = Kv.GetNum("Length");
				int time = Kv.GetNum("TimeStamp");
				int lefttime = ((length * 60) + time);
				
				if(lefttime > GetTime())
				{
					g_bIsClientRestricted[client] = true;
					
					DataPack datapack = new DataPack();
					g_hKbRestrictExpireTime[client] = CreateDataTimer(1.0 * (lefttime - GetTime()), KbRestrict_ExpireTimer, datapack);
					
					datapack.WriteCell(client);
					datapack.WriteString(SteamID);
				}
				else if(lefttime <= GetTime())
				{
					g_bIsClientRestricted[client] = false;
					Kv.DeleteThis();
					Kv.Rewind();
					Kv.ExportToFile(sPath);
				}
			}
			else if(Kv.GetNum("Length") == 0)
				g_bIsClientRestricted[client] = true;
		}
		delete Kv;
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action KbRestrict_ExpireTimer(Handle timer, DataPack datapack)
{
	char SteamID[32];
	datapack.Reset();
	int client = datapack.ReadCell();
	datapack.ReadString(SteamID, sizeof(SteamID));
	
	g_hKbRestrictExpireTime[client] = null;
	g_bIsClientRestricted[client] = false;
	
	if(IsValidClient(client))
	{
		CPrintToChat(client, "%s {green}%t.", KB_Tag, "Status unrestricted");
		DeletePlayerFromCFG(SteamID);
	}
	
	return Plugin_Continue;
}

//----------------------------------------------------------------------------------------------------
// Purpose :
//----------------------------------------------------------------------------------------------------	
stock void KbUnRestrictClient(int client, int target, const char[] reason = "No Reason")
{
	g_bIsClientRestricted[target] = false;
	delete g_hKbRestrictExpireTime[target];
	
	char SteamID[32];
	GetClientAuthId(target, AuthId_Steam2, SteamID, sizeof(SteamID));

	DeletePlayerFromCFG(SteamID);
	LogAction(client, target, "[Kb-Restrict] \"%L\" has unrestricted \"%L\" \nReason: \"%s\"", client, target, reason);
}

//----------------------------------------------------------------------------------------------------
// Purpose :
//----------------------------------------------------------------------------------------------------
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if(!g_bKnifeModeEnabled)
	{
		if(IsValidClient(victim) && IsValidClient(attacker) && attacker != victim)
		{
			if(IsPlayerAlive(attacker) && GetClientTeam(attacker) == 3 && g_bIsClientRestricted[attacker])
			{
				char sWeapon[32];
				GetClientWeapon(attacker, sWeapon, 32);
				if (StrEqual(sWeapon, "weapon_knife")) // Knife
					damage -= (damage * 0.95);
				if (StrEqual(sWeapon, "weapon_m3") || StrEqual(sWeapon, "weapon_xm1014")) // ShotGuns
					damage -= (damage * 0.80);
				if (StrEqual(sWeapon, "weapon_awp") || StrEqual(sWeapon, "weapon_scout")) // Snipers
					damage -= (damage * 0.60);
				if (StrEqual(sWeapon, "weapon_sg550") || StrEqual(sWeapon, "weapon_g3sg1")) // SemiAuto-Snipers
					damage -= (damage * 0.40);
				return Plugin_Changed;
			}
		}
	}
	
	return Plugin_Continue;
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------		
stock void Display_KbRestrictList_Menu(int client)
{
	Menu menu = new Menu(Menu_KbRestrictList);
	char sMenuTranslate[128], sMenuTemp1[64], sMenuTemp2[64], sMenuTemp3[64], sMenuTemp4[64];
	FormatEx(sMenuTranslate, sizeof(sMenuTranslate), "%t", "KbRestrict Commands Title");
	menu.SetTitle(sMenuTranslate);
	menu.ExitBackButton = true;
	
	FormatEx(sMenuTemp1, sizeof(sMenuTemp1), "%t", "KbBan a Player");
	menu.AddItem("0", sMenuTemp1);

	FormatEx(sMenuTemp2, sizeof(sMenuTemp2), "%t", "List of KbBan");
	menu.AddItem("1", sMenuTemp2, CheckCommandAccess(client, "sm_koban", ADMFLAG_RCON, true) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	FormatEx(sMenuTemp3, sizeof(sMenuTemp3), "%t", "Online KbBanned");
	menu.AddItem("2", sMenuTemp3);

	FormatEx(sMenuTemp4, sizeof(sMenuTemp4), "%t %t", "Your Own", "List of KbBan");
	menu.AddItem("3", sMenuTemp4);
	
	menu.Display(client, MENU_TIME_FOREVER);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if(!client)
		return Plugin_Continue;

	
	if(StrEqual(command, "say") || StrEqual(command, "say_team"))
	{
		if(g_bIsClientTypingReason[client])
		{	
			if(IsValidClient(GetClientOfUserId(g_iClientTargets[client])))
			{
				if(!g_bIsClientRestricted[GetClientOfUserId(g_iClientTargets[client])])
				{
					char buffer[128];
					strcopy(buffer, sizeof(buffer), sArgs);
					KbRestrictClient(client, GetClientOfUserId(g_iClientTargets[client]), g_iClientTargetsLength[client], buffer);
				}
				else
					CPrintToChat(client, "%s %t %t.", KB_Tag, "Player", "Already KbBanned");
			}
			else
				CPrintToChat(client, "%s %t.", KB_Tag, "Player is not valid anymore");
			
			g_bIsClientTypingReason[client] = false;
			return Plugin_Stop;
		}
	}
	
	return Plugin_Continue;
}

//----------------------------------------------------------------------------------------------------
// Purpose :
//----------------------------------------------------------------------------------------------------
stock void KbRestrictClient(int client, int target, int time = 0, const char[] reason = "No Reason")
{
	char sName[MAX_NAME_LENGTH], sAdminName[MAX_NAME_LENGTH], date[128], sCurrentMap[PLATFORM_MAX_PATH], SteamID[32];
	GetClientAuthId(target, AuthId_Steam2, SteamID, sizeof(SteamID));
	
	char AdminSteamID[32];
	if(client != 0)
	{
		GetClientAuthId(client, AuthId_Steam2, AdminSteamID, sizeof(AdminSteamID));
	}
				
	if(time >= 1)
	{
		CPrintToChatAll("%s {white}%N {red}%t {white}%N {red}%d %t. \n%s %t: %s.", KB_Tag, client, "Restricted", target, time, "Minutes", KB_Tag, "Reason", reason);
		LogAction(client, target, "[Kb-Restrict] \"%L\" restricted \"%L\" for \"%d\" minutes. \nReason: \"%s\"", client, target, time, reason);
		DataPack datapack = new DataPack();
		g_hKbRestrictExpireTime[target] = CreateDataTimer((1.0 * time * 60), KbRestrict_ExpireTimerOnline, datapack);
		datapack.WriteCell(target);
		datapack.WriteString(SteamID);
	}
	else if(time < 0)
	{
		CPrintToChatAll("%s {white}%N {red}%t %t {white}%N. \n%s %t: %s.", KB_Tag, client, "Temporary", "Restricted", target, KB_Tag, "Reason", reason);
		g_bIsClientRestricted[target] = true;
		LogAction(client, target, "[Kb-Restrict] \"%L\" temporarily restricted \"%L\" \nReason: \"%s\"", client, target, reason);
		return;
	}
	else if(time == 0)
	{
		CPrintToChatAll("%s {white}%N {red}%t %t {white}%N. \n%s %t: %s.", KB_Tag, client, "Permanently", "Restricted", target, KB_Tag, "Reason", reason);
		LogAction(client, target, "[Kb-Restrict] \"%L\" Permanently restricted \"%L\" \nReason: \"%s\"", client, target, reason);
	}
	
	g_bIsClientRestricted[target] = true;
	GetClientAuthId(target, AuthId_Steam2, SteamID, sizeof(SteamID));
	GetClientName(target, sName, sizeof(sName));
	GetClientName(client, sAdminName, sizeof(sAdminName));
	FormatTime(date, sizeof(date), "%d/%m/%y @ %r", GetTime());
	GetCurrentMap(sCurrentMap, sizeof(sCurrentMap));

	AddPlayerToCFG(SteamID, AdminSteamID, sName, sAdminName, reason, date, sCurrentMap, time);
}

//----------------------------------------------------------------------------------------------------
// Commands :
//----------------------------------------------------------------------------------------------------
public Action Command_CheckKbStatus(int client, int args)
{
	if(!client)
	{
		ReplyToCommand(client, "You cannot use this command from server console.");
		return Plugin_Handled;
	}
	
	char SteamID[32];
	GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID));
	
	if(!g_bIsClientRestricted[client])
	{
		CReplyToCommand(client, "%s {green}%t.", KB_Tag, "Status unrestricted");
		return Plugin_Handled;
	}
	else if(g_bIsClientRestricted[client])
	{
		CreateKv();
		if(Kv.JumpToKey(SteamID))
		{
			char sReason[64], sAdminName[32], TimeLeft[32];

			Kv.GetString("Reason", sReason, sizeof(sReason));
			Kv.GetString("Admin Name", sAdminName, sizeof(sAdminName));

			int time = Kv.GetNum("TimeStamp");
			int length = Kv.GetNum("Length");
			int totaltime = ((length * 60) + time);
			int lefttime = totaltime - GetTime();
			CheckPlayerExpireTime(lefttime, TimeLeft, sizeof(TimeLeft));				
			
			Display_CheckKbRestrict_Menu(client);
			CReplyToCommand(client, "%s %t.\n%s %t {white}%s.\n%s %t: %s.", KB_Tag, "Status restricted", KB_Tag, "Restricted By", sAdminName, KB_Tag, "Restricted Reason", sReason);
			CReplyToCommand(client, "%s {indianred}%t {green}%t %s.", KB_Tag, "Expires", "In", TimeLeft);
		}
		else
		{
			CReplyToCommand(client, "%s %t {red}%t. \n%s %t %t.", KB_Tag, "Status restricted", "Temporary", KB_Tag, "Expires", "On Map Change");
		}
		
		delete Kv;
		return Plugin_Handled;
	}
	
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Commands :
//----------------------------------------------------------------------------------------------------
public Action Command_KbRestrict(int client, int args)
{
	if(args < 1)
	{
		Display_KbRestrictList_Menu(client);
		CReplyToCommand(client, "%s Usage: sm_kban <player> <duration> <reason>", KB_Tag);
		return Plugin_Handled;
	}
	
	char Arguments[256], arg[50], s_time[20];
	GetCmdArgString(Arguments, sizeof(Arguments));
	
	int len, next_len;
	len = BreakString(Arguments, arg, sizeof(arg));
	if(len == -1)
    {
        len = 0;
        Arguments[0] = '\0';
    }
	
	if((next_len = BreakString(Arguments[len], s_time, sizeof(s_time))) != -1)
        len += next_len;
	else
    {
        len = 0;
        Arguments[0] = '\0';
    }

	int time = StringToInt(s_time);
	int target = FindTarget(client, arg, false, false);
	char SteamID[32];
	
	if(IsValidClient(target))
	{	
		if(!g_bIsClientRestricted[target])
		{
			if(!GetClientAuthId(target, AuthId_Steam2, SteamID, sizeof(SteamID)))
			{
				g_bIsClientRestricted[target] = true;
				CPrintToChatAll("%s {white}%N {red}%t {white}%N {red}%t.", KB_Tag, client, "Restricted", target, "Temporary");
				return Plugin_Handled;
			}
			else if(args < 2)
			{
				KbRestrictClient(client, target, g_cvDefaultLength.IntValue);
				return Plugin_Handled;
			}
			else if(args < 3)
			{
				if(!CheckCommandAccess(client, "sm_rcon", ADMFLAG_RCON, true) && time == 0)
				{	
					KbRestrictClient(client, target, g_cvAddBanLength.IntValue);		
					return Plugin_Handled;
				}

				char sReason[32];
				FormatEx(sReason, sizeof(sReason), "%t", "No Reason");
				KbRestrictClient(client, target, time, sReason);
				return Plugin_Handled;
			}
			
			if(!CheckCommandAccess(client, "sm_rcon", ADMFLAG_RCON, true) && time == 0)
			{	
				KbRestrictClient(client, target, g_cvAddBanLength.IntValue, Arguments[len]);
				return Plugin_Handled;
			}
			
			KbRestrictClient(client, target, time, Arguments[len]);
			return Plugin_Handled;
		}
		else
		{
			CReplyToCommand(client, "%s {white}%N {indianred}%t.", KB_Tag, target, "Already KbBanned");
			return Plugin_Handled;
		}
	}
	
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Commands :
//----------------------------------------------------------------------------------------------------
public Action Command_KbUnRestrict(int client, int args)
{
	if(args < 1)
	{
		Display_KbRestrictList_Menu(client);
		CReplyToCommand(client, "%s Usage: sm_kunban <player> <reason>.", KB_Tag);
		return Plugin_Handled;
	}
	
	char Arguments[256], arg[50];
	GetCmdArgString(Arguments, sizeof(Arguments));
	
	int len;
	len = BreakString(Arguments, arg, sizeof(arg));
	if(len == -1)
    {
        len = 0;
        Arguments[0] = '\0';
    }

	int target = FindTarget(client, arg, false, false);
	char SteamID[32], AdminSteamID[32];
	
	if(IsValidClient(target))
	{
		GetClientAuthId(target, AuthId_Steam2, SteamID, sizeof(SteamID));
		GetClientAuthId(client, AuthId_Steam2, AdminSteamID, sizeof(AdminSteamID));
		
		if(g_bIsClientRestricted[target])
		{
			if(!GetClientAuthId(target, AuthId_Steam2, SteamID, sizeof(SteamID)))
			{
				g_bIsClientRestricted[target] = false;
				CPrintToChatAll("%s {white}%N {green}%t {white}%N.", KB_Tag, client, "Unrestricted", target);
				return Plugin_Handled;
			}
			
			else if(!CheckKbRestrictAuthor(client, SteamID, AdminSteamID))
			{
				CReplyToCommand(client, "%s %t.", KB_Tag, "Not have permission !Own rKb-Ban");
				return Plugin_Handled;
			}
			
			else if(args < 2)
			{
				KbUnRestrictClient(client, target);
				CPrintToChatAll("%s {white}%N {green}%t {white}%N. \n%s %t: %t.", KB_Tag, client, "Unrestricted", target, KB_Tag, "Reason", "No Reason");
				return Plugin_Handled;
			}
			else if(args >= 2)
			{
				KbUnRestrictClient(client, target, Arguments[len]);
				CPrintToChatAll("%s {white}%N {green}%t {white}%N. \n%s %t: %s.", KB_Tag, client, "Unrestricted", target, KB_Tag, "Reason", Arguments[len]);
				return Plugin_Handled;
			}
		}
		else
		{
			CReplyToCommand(client, "%s %t {white}%N {indianred}%t.", KB_Tag, "Player", target, "Not Restricted");
			return Plugin_Handled;
		}
	}
	
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Commands :
//----------------------------------------------------------------------------------------------------
public Action Command_OfflineKbRestrict(int client, int args)
{
	if(args < 3)
	{
		CReplyToCommand(client, "%s Usage: sm_koban \"<steamid>\" <time> <reason>", KB_Tag);
		return Plugin_Handled;
	}

	char AdminSteamID[32];
	GetClientAuthId(client, AuthId_Steam2, AdminSteamID, sizeof(AdminSteamID));
	
	char Arguments[256], arg[50], s_time[20];
	GetCmdArgString(Arguments, sizeof(Arguments));
	
	int len, next_len;
	len = BreakString(Arguments, arg, sizeof(arg));
	if(len == -1)
    {
        len = 0;
        Arguments[0] = '\0';
    }
	
	if((next_len = BreakString(Arguments[len], s_time, sizeof(s_time))) != -1)
        len += next_len;
	else
    {
        len = 0;
        Arguments[0] = '\0';
    }
	
	int time = StringToInt(s_time);
	
	if(arg[7] != ':')
	{
		CReplyToCommand(client, "%s %t.", KB_Tag, "SteamID quotes");
		return Plugin_Handled;
	}
	
	CreateKv();
	if(Kv.JumpToKey(arg))
	{
		CReplyToCommand(client, "%s {grey}(%s) {indianred}%t.", KB_Tag, arg, "Already KbBanned");
		return Plugin_Handled;
	}
	else
	{
		if(time <= g_cvAddBanLength.IntValue)
		{
			if(!IsSteamIDInGame(arg))
			{
				char sAdminName[64], date[32], sCurrentMap[64];
				GetClientName(client, sAdminName, 64);
				FormatTime(date, 32, "%d/%m/%y @ %r", GetTime());
				GetCurrentMap(sCurrentMap, 64);
				
				AddPlayerToCFG(arg, AdminSteamID, "UnKnown", sAdminName, Arguments[len], date, sCurrentMap, time);
				CReplyToCommand(client, "%s {green}%t {grey}%s {red}%d %t", KB_Tag, "Offline Restricted", arg, time, "Minutes");
				LogAction(client, -1, "[Kb-Restrict] \"%L\" Offline restricted \"%s\" for \"%d\" minutes.", client, arg, time);
				return Plugin_Handled;
			}
			else // TO:DO If player is online, auto ban him with online ban function
			{
				CReplyToCommand(client, "%s The specified steamid is alraedy online on the server, please use {green}sm_kban {indianred}instead.", KB_Tag);
				return Plugin_Handled;
			}
		}
		else if(time > g_cvAddBanLength.IntValue)
		{
			CReplyToCommand(client, "%s %t %d %t", KB_Tag, "Not have permission lKb-Ban", g_cvAddBanLength.IntValue, "Minutes");
			return Plugin_Handled;
		}
	}
	delete Kv;
	
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
public int Menu_KbRestrictList(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;
		
		case MenuAction_Select:
		{
			switch(param2)
			{
				case 0:
					Display_KbRestrict_ClientsMenu(param1);
				case 1:
					Display_CurrentKbRestrict_Menu(param1);
				case 2:
					Display_AllKbRestrict_Menu(param1);
				case 3:
					Display_OwnKbRestrict_Menu(param1);
			}
		}
	}
	
	return 0;
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
stock void Display_KbRestrict_ClientsMenu(int client)
{
	Menu menu = new Menu(Menu_KbRestrictClients);
	char sMenuTranslate[128];
	FormatEx(sMenuTranslate, sizeof(sMenuTranslate), "%t %t:", "KB_Tag", "Restrict Player");
	menu.SetTitle(sMenuTranslate);
	menu.ExitBackButton = true;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && IsClientAuthorized(i) && !g_bIsClientRestricted[i])//2
		{
			char buffer[32], text[MAX_NAME_LENGTH];
			int userid = GetClientUserId(i);
			IntToString(userid, buffer, sizeof(buffer));
			FormatEx(text, sizeof(text), "%N", i);
			
			menu.AddItem(buffer, text);
		}
	}
			
	menu.Display(client, MENU_TIME_FOREVER);
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
stock void Display_CurrentKbRestrict_Menu(int client)
{
	Menu menu = new Menu(Menu_CurrentBans);
	char sMenuTranslate[128], sMenuTemp[64];
	FormatEx(sMenuTranslate, sizeof(sMenuTranslate), "%t %t:", "KB_Tag", "Online KbBanned");
	menu.SetTitle(sMenuTranslate);
	menu.ExitBackButton = true;
	
	if(GetCurrent_KbRestrict_Players() >= 1)
	{
		for (int player = 1; player <= MaxClients; player++)
		{
			if(IsValidClient(player) && g_bIsClientRestricted[player] && IsClientAuthorized(player))
			{
				char info[32], buffer[32];
				int userid = GetClientUserId(player);
				
				IntToString(userid, info, 32);
				FormatEx(buffer, 32, "%N", player);
				
				menu.AddItem(info, buffer);
			}
		}
	}
	else if(GetCurrent_KbRestrict_Players() <= 0)
	{
		FormatEx(sMenuTemp, sizeof(sMenuTemp), "%t", "No KbBans");	
		menu.AddItem("", sMenuTemp, ITEMDRAW_DISABLED);
	}
	
	menu.Display(client, MENU_TIME_FOREVER);
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
public int Menu_CurrentBans(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				Display_KbRestrictList_Menu(param1);
		}
		
		case MenuAction_End:
			delete menu;
		
		case MenuAction_Select:
		{
			char buffer[32];
			menu.GetItem(param2, buffer, sizeof(buffer));
			int userid = StringToInt(buffer);
			int target = GetClientOfUserId(userid);
			
			if(IsValidClient(target))
			{
				char SteamID[32];	
				GetClientAuthId(target, AuthId_Steam2, SteamID, sizeof(SteamID));
				
				ShowActionsAndDetailsForCurrent(param1, target, SteamID);
			}
		}
	}
	
	return 0;
}

stock void ShowActionsAndDetailsForCurrent(int client, int target, const char[] sSteamID)
{
	char SteamID[32];
	GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID));
	
	Menu menu = new Menu(Menu_ActionsAndDetailsCurrent);

	char sMenuTranslate[128];
	FormatEx(sMenuTranslate, sizeof(sMenuTranslate), "%t %t [%s]", "KB_Tag", "Details", sSteamID);
	menu.SetTitle(sMenuTranslate);
	menu.ExitBackButton = true;
	
	CreateKv();
	char sCurrentMap[PLATFORM_MAX_PATH], MapBuffer[PLATFORM_MAX_PATH + 64];
	char sName[MAX_NAME_LENGTH], sAdminName[MAX_NAME_LENGTH], NameBuffer[MAX_NAME_LENGTH + 64], AdminNameBuffer[MAX_NAME_LENGTH + 64];
	char AdminSteamID[32], sBuffer[32], LengthBuffer[64], TimeLeftBuffer[64], sLengthEx[64], UnbanTranslate[64], date[128], sReason[128], ReasonBuffer[150], DateBuffer[160];

	int userid = GetClientUserId(target);
	IntToString(userid, sBuffer, 32);
	
	int ilength;
	
	if(Kv.JumpToKey(sSteamID))
	{
		Kv.GetString("Name", sName, sizeof(sName));
		Kv.GetString("Admin Name", sAdminName, sizeof(sAdminName));
		Kv.GetString("AdminSteamID", AdminSteamID, sizeof(AdminSteamID));
		Kv.GetString("Reason", sReason, sizeof(sReason));
		Kv.GetString("Date", date, sizeof(date));
		Kv.GetString("Map", sCurrentMap, sizeof(sCurrentMap));
		Kv.GetString("LengthEx", sLengthEx, sizeof(sLengthEx));
		if(StrEqual(sLengthEx, "Permanent"))
			FormatEx(LengthBuffer, sizeof(LengthBuffer), "%t: %t", "Duration", "Permanently");
		else
		{
			ilength = Kv.GetNum("Length");
			FormatEx(LengthBuffer, sizeof(LengthBuffer), "%t: %d %t", "Duration", ilength, "Minutes");
		}
		
		int time = Kv.GetNum("TimeStamp");
		int length = Kv.GetNum("Length");
		int totaltime = ((length * 60) + time);
		int lefttime = totaltime - GetTime();
		
		char TimeLeft[32];
		CheckPlayerExpireTime(lefttime, TimeLeft, sizeof(TimeLeft));
				
		FormatEx(NameBuffer, sizeof(NameBuffer), "%t : %s", "Player", sName);
		FormatEx(AdminNameBuffer, sizeof(AdminNameBuffer), "%t : %s (%s)", "Admin", sAdminName, AdminSteamID);
		FormatEx(ReasonBuffer, sizeof(ReasonBuffer), "%t : %s", "Reason", sReason);
		FormatEx(DateBuffer, sizeof(DateBuffer), "%t : %s", "Issued", date);
		FormatEx(MapBuffer, sizeof(MapBuffer), "%t : %s", "Map", sCurrentMap);
		FormatEx(UnbanTranslate, sizeof(UnbanTranslate), "%t", "UnRestrict Player");
		if(StrEqual(sLengthEx, "Permanent"))
			FormatEx(TimeLeftBuffer, sizeof(TimeLeftBuffer), "%t : %t", "Expires", "Never");
		else
			FormatEx(TimeLeftBuffer, sizeof(TimeLeftBuffer), "%t %t : %s", "Expires", "In", TimeLeft);
				
		menu.AddItem("", NameBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", AdminNameBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", LengthBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", DateBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", TimeLeftBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", ReasonBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", MapBuffer, ITEMDRAW_DISABLED);
		menu.AddItem(sBuffer, UnbanTranslate, CheckKbRestrictAuthor(client, sSteamID, SteamID) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}
	else
	{
		GetCurrentMap(sCurrentMap, sizeof(sCurrentMap));
		FormatEx(LengthBuffer, sizeof(LengthBuffer), "%t : %t", "Duration", "Temporary");
		FormatEx(TimeLeftBuffer, sizeof(TimeLeftBuffer), "%t : %t", "Expires", "On Map Change");
		FormatEx(MapBuffer, sizeof(MapBuffer), "%t : %s", "Map", sCurrentMap);
		menu.AddItem("", LengthBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", TimeLeftBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", MapBuffer, ITEMDRAW_DISABLED);
	}
	
	delete Kv;
	
	menu.Display(client, MENU_TIME_FOREVER);
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
public int Menu_ActionsAndDetailsCurrent(Menu menu, MenuAction action, int param1, int param2) // RENAME
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;
		
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				Display_CurrentKbRestrict_Menu(param1);
		}
		
		case MenuAction_Select:
		{
			char buffer[32];
			menu.GetItem(param2, buffer, sizeof(buffer));
			
			int userid = StringToInt(buffer);
			int target = GetClientOfUserId(userid);
			
			char SteamID[32];
			GetClientAuthId(target, AuthId_Steam2, SteamID, sizeof(SteamID));
			
			if(g_bIsClientRestricted[target])
			{
				DeletePlayerFromCFG(SteamID);
				g_bIsClientRestricted[target] = false;
				
				CPrintToChatAll("%s {white}%N {green}%t {white}%N. \n%s %t: %t.", KB_Tag, param1, "Unrestricted", target, KB_Tag, "Reason", "No Reason");
				LogAction(param1, target, "[Kb-Restrict] \"%L\" unrestricted \"%L\" \nReason: No Reason.", param1, target);
			}
				
			Display_CurrentKbRestrict_Menu(param1);
		}
	}
	
	return 0;
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
stock void Display_OwnKbRestrict_Menu(int client)
{
	char sSteamID[32];
	GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID));
	
	Menu menu = new Menu(Menu_Own_KbRestrict);
	char sMenuTranslate[128], sMenuTemp[64];
	FormatEx(sMenuTranslate, sizeof(sMenuTranslate), "%t %t %t", "KB_Tag", "Your Own", "List of KbBan");
	menu.SetTitle(sMenuTranslate);
	menu.ExitBackButton = true;
	
	if(GetAdminOwn_KbRestrict(client, sSteamID) >= 1)
	{
		CreateKv();
		if(Kv.GotoFirstSubKey())
		{
			do
			{
				char sName[64], buffer[128], SteamID[32], AdminSteamID[32];
				Kv.GetSectionName(SteamID, sizeof(SteamID));
				Kv.GetString("Name", sName, sizeof(sName));
				Kv.GetString("AdminSteamID", AdminSteamID, sizeof(AdminSteamID));
				if(StrEqual(AdminSteamID, sSteamID))
				{
					if(IsSteamIDInGame(SteamID))
						FormatEx(buffer, sizeof(buffer), "%s (%t)", sName, "Online");
					else
						FormatEx(buffer, sizeof(buffer), "%s [%s] (%t)", sName, SteamID, "Offline");
						
					menu.AddItem(SteamID, buffer);
				}
			}
			while(Kv.GotoNextKey());
		}
		
		delete Kv;
	}
	else if(GetAdminOwn_KbRestrict(client, sSteamID) <= 0)
	{
		FormatEx(sMenuTemp, sizeof(sMenuTemp), "%t", "No KbBans");	
		menu.AddItem("", sMenuTemp, ITEMDRAW_DISABLED);
	}
	
	menu.Display(client, MENU_TIME_FOREVER);
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
stock void Display_AllKbRestrict_Menu(int client)
{
	Menu menu = new Menu(Menu_All_KbRestrict);
	char sMenuTranslate[128], sMenuTemp[64];
	FormatEx(sMenuTranslate, sizeof(sMenuTranslate), "%t %t", "KB_Tag", "List of KbBan");
	menu.SetTitle(sMenuTranslate);
	menu.ExitBackButton = true;
	
	CreateKv();
	if(!Kv.GotoFirstSubKey())
	{
		FormatEx(sMenuTranslate, sizeof(sMenuTranslate), "%t", "Empty");
		FormatEx(sMenuTemp, sizeof(sMenuTemp), "%t", "No KbBans");
		menu.AddItem(sMenuTranslate, sMenuTemp, ITEMDRAW_DISABLED);
	}
	else
	{
		do
		{
			char sName[64], buffer[128], SteamID[32];
			Kv.GetSectionName(SteamID, sizeof(SteamID));
			Kv.GetString("Name", sName, sizeof(sName));
			
			FormatEx(buffer, sizeof(buffer), "%s [%s]", sName, SteamID);
			menu.AddItem(SteamID, buffer);
		}
		while(Kv.GotoNextKey());
	}
	
	delete Kv;
	
	menu.Display(client, MENU_TIME_FOREVER);
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------			
public int Menu_All_KbRestrict(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				Display_KbRestrictList_Menu(param1);
		}
		
		case MenuAction_End:
			delete menu;
		
		case MenuAction_Select:
		{			
			char buffer[32];
			menu.GetItem(param2, buffer, sizeof(buffer));
			
			ShowActionsAndDetailsForAll(param1, buffer);
		}
	}
	
	return 0;
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------	
stock void ShowActionsAndDetailsForAll(int client, const char[] sSteamID)
{
	Menu menu = new Menu(Menu_ActionsAndDetailsAll);
	
	char sMenuTranslate[128];
	FormatEx(sMenuTranslate, sizeof(sMenuTranslate), "%t %t [%s]", "KB_Tag", "Details", sSteamID);
	menu.SetTitle(sMenuTranslate);
	menu.ExitBackButton = true;
	
	CreateKv();
	char sCurrentMap[PLATFORM_MAX_PATH], MapBuffer[PLATFORM_MAX_PATH + 64];
	char sName[MAX_NAME_LENGTH], sAdminName[MAX_NAME_LENGTH], NameBuffer[MAX_NAME_LENGTH + 64], AdminNameBuffer[MAX_NAME_LENGTH + 64];
	char AdminSteamID[32], LengthBuffer[64], TimeLeftBuffer[64], sLengthEx[64], UnbanTranslate[64], date[128], sReason[128], ReasonBuffer[150], DateBuffer[160];

	int ilength;
	
	if(Kv.JumpToKey(sSteamID))
	{
		Kv.GetString("Name", sName, sizeof(sName));
		Kv.GetString("Admin Name", sAdminName, sizeof(sAdminName));
		Kv.GetString("AdminSteamID", AdminSteamID, sizeof(AdminSteamID));
		Kv.GetString("Reason", sReason, sizeof(sReason));
		Kv.GetString("Date", date, sizeof(date));
		Kv.GetString("Map", sCurrentMap, sizeof(sCurrentMap));

		Kv.GetString("LengthEx", sLengthEx, sizeof(sLengthEx));
		if(StrEqual(sLengthEx, "Permanent"))
			FormatEx(LengthBuffer, sizeof(LengthBuffer), "%t: %t", "Duration", "Permanently");
		else
		{
			ilength = Kv.GetNum("Length");
			FormatEx(LengthBuffer, sizeof(LengthBuffer), "%t: %d %t", "Duration", ilength, "Minutes");
		}
		
		int time = Kv.GetNum("TimeStamp");
		int length = Kv.GetNum("Length");
		int totaltime = ((length * 60) + time);
		int lefttime = totaltime - GetTime();
		
		char TimeLeft[32];
		CheckPlayerExpireTime(lefttime, TimeLeft, sizeof(TimeLeft));

		FormatEx(NameBuffer, sizeof(NameBuffer), "%t : %s", "Player", sName);
		FormatEx(AdminNameBuffer, sizeof(AdminNameBuffer), "%t : %s (%s)", "Admin", sAdminName, AdminSteamID);
		FormatEx(ReasonBuffer, sizeof(ReasonBuffer), "%t : %s", "Reason", sReason);
		FormatEx(DateBuffer, sizeof(DateBuffer), "%t : %s", "Issued", date);
		FormatEx(MapBuffer, sizeof(MapBuffer), "%t : %s", "Map", sCurrentMap);
		FormatEx(UnbanTranslate, sizeof(UnbanTranslate), "%t", "UnRestrict Player");
		if(StrEqual(sLengthEx, "Permanent"))
			FormatEx(TimeLeftBuffer, sizeof(TimeLeftBuffer), "%t : %t", "Expires", "Never");
		else
			FormatEx(TimeLeftBuffer, sizeof(TimeLeftBuffer), "%t %t : %s", "Expires", "In", TimeLeft);
				
		menu.AddItem("", NameBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", AdminNameBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", LengthBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", DateBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", TimeLeftBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", ReasonBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", MapBuffer, ITEMDRAW_DISABLED);
		menu.AddItem(sSteamID, UnbanTranslate);
	}
	
	delete Kv;
	
	menu.Display(client, MENU_TIME_FOREVER);
}

//----------------------------------------------------------------------------------------------------
// Purpose :
//----------------------------------------------------------------------------------------------------
public int Menu_ActionsAndDetailsAll(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;
		
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				Display_AllKbRestrict_Menu(param1);
		}
		
		case MenuAction_Select:
		{
			char buffer[32];
			menu.GetItem(param2, buffer, sizeof(buffer));
			
			DeletePlayerFromCFG(buffer);
			CPrintToChat(param1, "%s {green}%t {grey}%s.", KB_Tag, "Unrestricted", buffer);
			if(!IsSteamIDInGame(buffer))
			{
				LogAction(param1, -1, "[Kb-Restrict] \"%L\" unrestricted \"%s\" \nReason : No Reason", param1, buffer);
			}
			else
			{
				int target = GetPlayerFromSteamID(buffer);
				if(g_bIsClientRestricted[target])
				{
					LogAction(param1, -1, "[Kb-Restrict] \"%L\" unrestricted \"%s\" (Player is in-game) \nReason : No Reason", param1, buffer);
					CPrintToChatAll("%s {white}%N {green}%t {white}%N. \n%s %t: %t.", KB_Tag, param1, "Unrestricted", target, KB_Tag, "Reason", "No Reason");
					g_bIsClientRestricted[target] = false;
					g_hKbRestrictExpireTime[target] = null;
				}
			}
			
			Display_AllKbRestrict_Menu(param1);
		}
	}
	
	return 0;
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
public int Menu_KbRestrictClients(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;
		
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				Display_KbRestrictList_Menu(param1);
		}
		
		case MenuAction_Select:
		{
			char buffer[64];
			menu.GetItem(param2, buffer, sizeof(buffer));
			int userid = StringToInt(buffer);
			int target = GetClientOfUserId(userid);
			
			if(IsValidClient(target) && !IsFakeClient(target) && IsClientAuthorized(target))
			{
				if(!g_bIsClientRestricted[target])
				{
					DisplayLengths_Menu(param1);
					g_iClientTargets[param1] = userid;
				}
				else
				{
					CPrintToChat(param1, "%s %t.", KB_Tag, "Already KbBanned");
					Display_KbRestrict_ClientsMenu(param1);
				}
			}
			else
			{
				Display_KbRestrict_ClientsMenu(param1);
				CPrintToChat(param1, "%s %t.", KB_Tag, "Player is not valid anymore");
			}
		}
	}
	
	return 0;
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
stock void DisplayLengths_Menu(int client)
{
	Menu menu = new Menu(Menu_KbRestrict_Lengths);
	char sMenuTranslate[128];
	FormatEx(sMenuTranslate, sizeof(sMenuTranslate), "%t %t", "KB_Tag", "KbBan Duration");
	menu.SetTitle(sMenuTranslate);
	menu.ExitBackButton = true;
	
	char LengthBufferP[64], LengthBufferT[64];
	FormatEx(LengthBufferP, sizeof(LengthBufferP), "%t", "Permanently");
	FormatEx(LengthBufferT, sizeof(LengthBufferT), "%t", "Temporary");

	menu.AddItem("0", LengthBufferP, CheckCommandAccess(client, "sm_koban", ADMFLAG_RCON, true) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("-1", LengthBufferT);
	
	for(int i = 15; i >= 15 && i < 241920; i++)
	{
		if(i == 15 || i == 30 || i == 45)
		{
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			FormatEx(text, sizeof(text), "%d %t", i, "Minutes");
			menu.AddItem(buffer, text);
		}
		else if(i == 60)
		{
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int hour = (i / 60);
			FormatEx(text, sizeof(text), "%d %t", hour, "Hour");
			menu.AddItem(buffer, text);
		}
		else if(i == 120 || i == 240 || i == 480 || i == 720)
		{
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int hour = (i / 60);
			FormatEx(text, sizeof(text), "%d %t", hour, "Hours");
			menu.AddItem(buffer, text);
		}
		else if(i == 1440)
		{
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int day = (i / 1440);
			FormatEx(text, sizeof(text), "%d %t", day, "Day");
			menu.AddItem(buffer, text);
		}
		else if(i == 2880 || i == 4320 || i == 5760 || i == 7200 || i == 8640)
		{
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int day = (i / 1440);
			FormatEx(text, sizeof(text), "%d %t", day, "Days");
			menu.AddItem(buffer, text);
		}
		else if(i == 10080)
		{
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int week = (i / 10080);
			FormatEx(text, sizeof(text), "%d %t", week, "Week");
			menu.AddItem(buffer, text);
		}
		else if(i == 20160 || i == 30240)
		{
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int week = (i / 10080);
			FormatEx(text, sizeof(text), "%d %t", week, "Weeks");
			menu.AddItem(buffer, text);
		}
		else if(i == 40320)
		{
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int month = (i / 40320);
			FormatEx(text, sizeof(text), "%d %t", month, "Month");
			menu.AddItem(buffer, text);
		}
		else if(i == 80640 || i == 120960 || i == 241920)
		{
			char buffer[32], text[32];
			IntToString(i, buffer, sizeof(buffer));
			int month = (i / 40320);
			FormatEx(text, sizeof(text), "%d %t", month, "Months");
			menu.AddItem(buffer, text);
		}
	}
	
	menu.Display(client, MENU_TIME_FOREVER);
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
public int Menu_KbRestrict_Lengths(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;
			
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				Display_KbRestrict_ClientsMenu(param1);
		}
		
		case MenuAction_Select:
		{		
			char buffer[64];
			menu.GetItem(param2, buffer, sizeof(buffer));
			int time = StringToInt(buffer);
			
			if(IsValidClient(GetClientOfUserId(g_iClientTargets[param1])))
			{
				g_iClientTargetsLength[param1] = time;
				DisplayReasons_Menu(param1);
			}
		}
	}
	
	return 0;
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
stock void DisplayReasons_Menu(int client)
{
	Menu menu = new Menu(Menu_Reasons);
	char sMenuTranslate[128];
	FormatEx(sMenuTranslate, sizeof(sMenuTranslate), "%t %t", "KB_Tag", "Restricted Reason");
	menu.SetTitle(sMenuTranslate);
	menu.ExitBackButton = true;
	
	char sBuffer[128];
	
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "Boosting", client);
	menu.AddItem(sBuffer, sBuffer);
	
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "TryingToBoost", client);
	menu.AddItem(sBuffer, sBuffer);

	FormatEx(sBuffer, sizeof(sBuffer), "%t", "Trimming team", client);
	menu.AddItem(sBuffer, sBuffer);

	FormatEx(sBuffer, sizeof(sBuffer), "%t", "Trolling on purpose", client);
	menu.AddItem(sBuffer, sBuffer);
	
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "Custom Reason", client);
	menu.AddItem("4", sBuffer);
	
	menu.Display(client, MENU_TIME_FOREVER);
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
public int Menu_Own_KbRestrict(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;
		
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				Display_KbRestrictList_Menu(param1);
		}
		
		case MenuAction_Select:
		{
			char buffer[32];
			menu.GetItem(param2, buffer, sizeof(buffer));
			
			DisplayOwn_KbRestrict_Actions(param1, buffer);
		}
	}
	
	return 0;
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
stock void DisplayOwn_KbRestrict_Actions(int client, const char[] SteamID)
{
	Menu menu = new Menu(Menu_Own_KbRestrictActions);
	char sMenuTranslate[128];
	FormatEx(sMenuTranslate, sizeof(sMenuTranslate), "%t %t [%s]", "KB_Tag", "Details", SteamID);
	menu.SetTitle(sMenuTranslate);
	menu.ExitBackButton = true;
	
	CreateKv();
	char sCurrentMap[PLATFORM_MAX_PATH], sName[MAX_NAME_LENGTH], MapBuffer[PLATFORM_MAX_PATH + 64], NameBuffer[MAX_NAME_LENGTH + 64];
	char LengthBuffer[64], TimeLeftBuffer[64], sLengthEx[64], UnbanTranslate[64], date[128], sReason[128], ReasonBuffer[150], DateBuffer[160];

	int ilength;
	
	Kv.JumpToKey(SteamID, true);
	Kv.GetString("Name", sName, sizeof(sName));
	Kv.GetString("Reason", sReason, sizeof(sReason));
	Kv.GetString("Date", date, sizeof(date));
	Kv.GetString("Map", sCurrentMap, sizeof(sCurrentMap));
	Kv.GetString("LengthEx", sLengthEx, sizeof(sLengthEx));
	if(StrEqual(sLengthEx, "Permanent"))
		FormatEx(LengthBuffer, sizeof(LengthBuffer), "%t: %t", "Duration", "Permanently");
	else
	{
		ilength = Kv.GetNum("Length");
		FormatEx(LengthBuffer, sizeof(LengthBuffer), "%t: %d %t", "Duration", ilength, "Minutes");
	}

	int time = Kv.GetNum("TimeStamp");
	int length = Kv.GetNum("Length");
	int totaltime = ((length * 60) + time);
	int lefttime = totaltime - GetTime();

	char TimeLeft[32];
	CheckPlayerExpireTime(lefttime, TimeLeft, sizeof(TimeLeft));

	FormatEx(NameBuffer, sizeof(NameBuffer), "%t : %s", "Player", sName);
	FormatEx(ReasonBuffer, sizeof(ReasonBuffer), "%t : %s", "Reason", sReason);
	FormatEx(DateBuffer, sizeof(DateBuffer), "%t : %s", "Issued", date);
	FormatEx(MapBuffer, sizeof(MapBuffer), "%t : %s", "Map", sCurrentMap);
	FormatEx(UnbanTranslate, sizeof(UnbanTranslate), "%t", "UnRestrict Player");
	if(StrEqual(sLengthEx, "Permanent"))
		FormatEx(TimeLeftBuffer, sizeof(TimeLeftBuffer), "%t : %t", "Expires", "Never");
	else
		FormatEx(TimeLeftBuffer, sizeof(TimeLeftBuffer), "%t %t : %s", "Expires", "In", TimeLeft);
			
	menu.AddItem("", NameBuffer, ITEMDRAW_DISABLED);
	menu.AddItem("", LengthBuffer, ITEMDRAW_DISABLED);
	menu.AddItem("", DateBuffer, ITEMDRAW_DISABLED);
	menu.AddItem("", TimeLeftBuffer, ITEMDRAW_DISABLED);
	menu.AddItem("", ReasonBuffer, ITEMDRAW_DISABLED);
	menu.AddItem("", MapBuffer, ITEMDRAW_DISABLED);
	menu.AddItem(SteamID, UnbanTranslate);

	delete Kv;
	
	menu.Display(client, MENU_TIME_FOREVER);
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
public int Menu_Own_KbRestrictActions(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;
		
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				Display_OwnKbRestrict_Menu(param1);
		}
		
		case MenuAction_Select:
		{
			char buffer[32];
			menu.GetItem(param2, buffer, sizeof(buffer));
			
			if(IsSteamIDInGame(buffer))
			{
				int target = GetPlayerFromSteamID(buffer);
				if(IsValidClient(target))
				{
					char sReason[32];
					FormatEx(sReason, sizeof(sReason), "%t", "No Reason");
					KbUnRestrictClient(param1, target, sReason);
					CPrintToChatAll("%s {white}%N {green}%t {white}%N. \n%s %t: %t.", KB_Tag, param1, "Unrestricted", target, KB_Tag, "Reason", "No Reason");
				}
			}
			else
			{
				DeletePlayerFromCFG(buffer);
				CPrintToChat(param1, "%s {green}%t {white}%s.", KB_Tag, "Unrestricted", buffer);
			}
			
			Display_OwnKbRestrict_Menu(param1);
		}
	}
	
	return 0;
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
public int Menu_Reasons(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			g_bIsClientTypingReason[param1] = false;
			delete menu;
		}
		
		case MenuAction_Cancel:
		{		
			if(param2 == MenuCancel_ExitBack)
			{
				g_bIsClientTypingReason[param1] = false;
				
				if(IsValidClient(GetClientOfUserId(g_iClientTargets[param1])))
					DisplayLengths_Menu(param1);
			}
		}
		
		case MenuAction_Select:
		{
			if(param2 == 4)
			{
				if(IsValidClient(GetClientOfUserId(g_iClientTargets[param1])))
				{
					if(!g_bIsClientRestricted[GetClientOfUserId(g_iClientTargets[param1])])
					{
						CPrintToChat(param1, "%s %t.", KB_Tag, "ChatReason");
						g_bIsClientTypingReason[param1] = true;
					}
					else
						CPrintToChat(param1, "%s %t.", KB_Tag, "Already KbBanned");
				}
				else
					CPrintToChat(param1, "%s %t.", KB_Tag, "Player is not valid anymore");
			}
			else
			{
			
				char buffer[128];
				menu.GetItem(param2, buffer, sizeof(buffer));
				
				if(IsValidClient(GetClientOfUserId(g_iClientTargets[param1])))
					KbRestrictClient(param1, GetClientOfUserId(g_iClientTargets[param1]), g_iClientTargetsLength[param1], buffer);
			}
		}
	}
	
	return 0;
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
public int Menu_Check_KbRestrict(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;
	}
	
	return 0;
}

//----------------------------------------------------------------------------------------------------
// Menu :
//----------------------------------------------------------------------------------------------------
stock void Display_CheckKbRestrict_Menu(int client)
{
	Menu menu = new Menu(Menu_Check_KbRestrict);
	char sMenuTranslate[128];
	FormatEx(sMenuTranslate, sizeof(sMenuTranslate), "%t %t %t", "KB_Tag", "Your Own", "Details");
	menu.SetTitle(sMenuTranslate);
	menu.ExitBackButton = true;
	
	char SteamID[32];
	GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID));
	
	char sCurrentMap[PLATFORM_MAX_PATH], MapBuffer[PLATFORM_MAX_PATH + 64];
	char sName[MAX_NAME_LENGTH], sAdminName[MAX_NAME_LENGTH], NameBuffer[MAX_NAME_LENGTH + 64], AdminNameBuffer[MAX_NAME_LENGTH + 64];
	char AdminSteamID[32], LengthBuffer[64], TimeLeftBuffer[64], sLengthEx[64], date[128], sReason[128], ReasonBuffer[150], DateBuffer[160];
		
	int ilength;
	
	CreateKv();
	if(Kv.JumpToKey(SteamID))
	{
		Kv.GetString("Name", sName, sizeof(sName));
		Kv.GetString("Admin Name", sAdminName, sizeof(sAdminName));
		Kv.GetString("AdminSteamID", AdminSteamID, sizeof(AdminSteamID));
		Kv.GetString("Reason", sReason, sizeof(sReason));
		Kv.GetString("Date", date, sizeof(date));
		Kv.GetString("Map", sCurrentMap, sizeof(sCurrentMap));
		Kv.GetString("LengthEx", sLengthEx, sizeof(sLengthEx));
		if(StrEqual(sLengthEx, "Permanent"))
			FormatEx(LengthBuffer, sizeof(LengthBuffer), "%t: %t", "Duration", "Permanently");
		else
		{
			ilength = Kv.GetNum("Length");
			FormatEx(LengthBuffer, sizeof(LengthBuffer), "%t: %d %t", "Duration", ilength, "Minutes");
		}

		int time = Kv.GetNum("TimeStamp");
		int length = Kv.GetNum("Length");
		int totaltime = ((length * 60) + time);
		int lefttime = totaltime - GetTime();
		
		char TimeLeft[32];
		CheckPlayerExpireTime(lefttime, TimeLeft, sizeof(TimeLeft));

		FormatEx(NameBuffer, sizeof(NameBuffer), "%t : %s", "Player", sName);
		FormatEx(AdminNameBuffer, sizeof(AdminNameBuffer), "%t : %s (%s)", "Admin", sAdminName, AdminSteamID);
		FormatEx(ReasonBuffer, sizeof(ReasonBuffer), "%t : %s", "Reason", sReason);
		FormatEx(DateBuffer, sizeof(DateBuffer), "%t : %s", "Issued", date);
		FormatEx(MapBuffer, sizeof(MapBuffer), "%t : %s", "Map", sCurrentMap);
		if(StrEqual(sLengthEx, "Permanent"))
			FormatEx(TimeLeftBuffer, sizeof(TimeLeftBuffer), "%t : %t", "Expires", "Never");
		else
			FormatEx(TimeLeftBuffer, sizeof(TimeLeftBuffer), "%t %t : %s", "Expires", "In", TimeLeft);
		
		menu.AddItem("", NameBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", AdminNameBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", LengthBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", DateBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", TimeLeftBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", ReasonBuffer, ITEMDRAW_DISABLED);
		menu.AddItem("", MapBuffer, ITEMDRAW_DISABLED);
	}
	
	menu.Display(client, 32);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnMapEnd()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
			delete g_hKbRestrictExpireTime[i];		
	}
	
	g_aSteamIDs.Clear();
	delete g_aSteamIDs;
	delete Kv;
}

//----------------------------------------------------------------------------------------------------
// Purpose :
//----------------------------------------------------------------------------------------------------
stock bool IsValidClient(int client)
{
	return (1 <= client <= MaxClients && IsClientInGame(client) && !IsClientSourceTV(client) && !IsFakeClient(client));
}

//----------------------------------------------------------------------------------------------------
// Forwards :
//----------------------------------------------------------------------------------------------------
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("KbRestrict");

	CreateNative("Kb_BanClient", Native_KB_BanClient);
	CreateNative("Kb_UnBanClient", Native_KB_UnBanClient);
	CreateNative("Kb_ClientStatus", Native_KB_ClientStatus);
	
	return APLRes_Success;
}

//----------------------------------------------------------------------------------------------------
// Native :
//----------------------------------------------------------------------------------------------------

public int Native_KB_BanClient(Handle plugin, int params)
{
	char sReason[128];
		
	int admin = GetNativeCell(1);
	int client = GetNativeCell(2);
	int time = GetNativeCell(3);
	GetNativeString(4, sReason, sizeof(sReason));

	if(g_bIsClientRestricted[client])
		return 0;
		
	if(!IsClientAuthorized(client))
		return 0;
	
	KbRestrictClient(admin, client, time, sReason);
	return 1;
}

//----------------------------------------------------------------------------------------------------
// Native :
//----------------------------------------------------------------------------------------------------

public int Native_KB_UnBanClient(Handle plugin, int params)
{
	char sReason[128];
		
	int admin = GetNativeCell(1);
	int client = GetNativeCell(2);
	GetNativeString(3, sReason, sizeof(sReason));

	if(!g_bIsClientRestricted[client])
		return 0;
		
	KbUnRestrictClient(admin, client, sReason);
	return 1;
}

//----------------------------------------------------------------------------------------------------
// Native :
//----------------------------------------------------------------------------------------------------

public int Native_KB_ClientStatus(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	return g_bIsClientRestricted[client];
}