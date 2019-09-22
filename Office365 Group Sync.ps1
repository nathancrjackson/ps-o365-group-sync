param(
	[string]	$LogFile = "",
	[string]	$ConfigFile = "",
	[string]	$FilenameAppend = "",
	[string]	$Commit = "No",
	[string]	$Username = "",
	[string]	$Password = "",
	[System.Management.Automation.PSCredential]	$Credentials = $NULL,
	[bool]		$Connect = $TRUE,
	[bool]		$Disconnect = $TRUE,
	[bool]		$Debug = $FALSE
)

#
# Office 365 Group Sync Utility
# version 1.0.0
#
# Requirements:
#	- Install-Module AzureAD
#

<# ---------------------------------
	SCRIPT VARIABLES
--------------------------------- #>

$Script:ConfigData = $NULL
$Script:UserDetails = @{}
$Script:GroupDetails = @{}
$Script:GroupMemberships = @{}
$Script:GroupMappings = @{}
$Script:GlobalGroups = @()
$Script:GlobalUsers = @()

<# ---------------------------------
	SCRIPT LOGIC
--------------------------------- #>

FUNCTION Main
{
	#First we need to sort out our log filename
	IF ($Script:LogFile -EQ "")
	{
		IF ($Script:FilenameAppend -EQ "")
		{
			#Default config name
			$Script:LogFile = GetFilename -Extension "log"
		}
		ELSE
		{
			#Config name with FilenameAppend appended
			$Script:LogFile = GetFilename -Extension "$($Script:FilenameAppend).log"
		}
	}
	
	DebugOutput "Log Filename is: $($Script:LogFile)"

	$CurrentTimestamp = Get-Date -DisplayHint Date -Format "dd-MM-yyyy HH:mm:ss"
	ReportToLog "Script started at: $CurrentTimestamp"

	$AADModuleFound = Check-AzureADModule

	IF ($AADModuleFound -EQ $TRUE)
	{
		$ConfigLoaded = LoadConfig
		IF ($ConfigLoaded -EQ $TRUE)
		{
			$Script:Connected = Manage-AzureADConnection
			IF ($Script:Connected -EQ $TRUE)
			{
				Load-AzureADObjects

				$MappingsValid = Validate-Mappings

				IF ($MappingsValid -EQ $TRUE)
				{
					Memberships-Handle
				}
			}

			#Had a weird bug where so broke this into seperate IF statements
			IF (Check-AzureADService -EQ $TRUE)
			{
				IF ($Script:Disconnect -EQ $TRUE)
				{
					Disconnect-AzureADService
				}
			}
		}
	}
	ELSE
	{
		ReportToLog "AZUREAD POWERSHELL MODULE REQUIRED FOR THIS SCRIPT"
		ReportToLog "Please run the following command in PowerShell as Admin:"
		ReportToLog "Install-Module AzureAD"
	}

	$CurrentTimestamp = Get-Date -DisplayHint Date -Format "dd-MM-yyyy HH:mm:ss"
	ReportToLog "Script finished at: $CurrentTimestamp`n---"
}

FUNCTION LoadConfig
{
	#Prep some variables and check for Azure AD module
	$CONTINUE = $TRUE
	$ConfigContent = $NULL

	#Check that commit value is valid
	IF (!(@("yes","no","prompt").Contains($Script:Commit.ToLower())))
	{
		ReportToLog "COMMIT MUST BE SET TO YES, NO OR PROMPT"
		$CONTINUE = $FALSE
	}
	ELSEIF ($Script:Commit -MATCH "no")
	{
		$Line1 = "PLEASE NOTE CHANGES WILL NOT BE COMMITTED!"
		Write-Host "#`n# $Line1`n#"
	}

	#Try read the config file
	ReportToLog "Loading script config"

	TRY
	{
		IF ($Script:ConfigFile -EQ "")
		{
			IF ($Script:FilenameAppend -EQ "")
			{
				#Default config name
				$Script:ConfigFile = GetFilename -Extension "config.json"
			}
			ELSE
			{
				#Config name with FilenameAppend appended
				$Script:ConfigFile = GetFilename -Extension "$($Script:FilenameAppend).config.json"
			}
		}

		DebugOutput "Config Filename is: $($Script:ConfigFile)"
	
		$ConfigContent = Get-Content -Raw -Path $Script:ConfigFile -ErrorAction Stop
	}
	CATCH
	{
		ReportToLog "COULD NOT FIND CONFIG FILE"
		$CONTINUE = $FALSE
	}

	#Try parse the config file
	IF ($CONTINUE -EQ $TRUE)
	{
		TRY
		{
			$Script:ConfigData  = ConvertFrom-Json -InputObject $ConfigContent
		}
		CATCH
		{
			ReportToLog "CONFIG FILE NOT VALID JSON"
			$CONTINUE = $FALSE
		}
	}

	#Validate the config file
	IF ($CONTINUE -EQ $TRUE)
	{

		IF ($Script:ConfigData.TenantPrefix -EQ $NULL)
		{
			ReportToLog "CONFIG FILE MISSING TENANT PREFIX"
			$CONTINUE = $FALSE
		}

		IF ($Script:ConfigData.Mappings -EQ $NULL)
		{
			ReportToLog "CONFIG FILE MISSING MAPPINGS"
		}
		ELSEIF ($CONTINUE -EQ $TRUE)
		{
			TRY
			{
				# Load Office365 Group Mappings
				ReportToLog "Loading Mappings from config"

				FOREACH ($Map in $Script:ConfigData.Mappings)
				{
					IF ($Map.Parent -NE $NULL)
					{
						$Script:GroupMappings.Add( $Map.Parent, @{Groups = $Map.ChildGroups; Users = $Map.ChildUsers} )
					}
					ELSE
					{
						ReportToLog "AT LEAST ONE MAPPING MISSING PARENT VALUE"
						RETURN $FALSE
					}
				}

				IF ($Script:ConfigData.GlobalGroups -NE $NULL)
				{
					FOREACH ($Group IN $Script:ConfigData.GlobalGroups)
					{
						IF ($Script:GlobalGroups.Contains($Group) -EQ $FALSE)
						{
							$Script:GlobalGroups += $Group
						}
					}
				}

				IF ($Script:ConfigData.GlobalUsers -NE $NULL)
				{
					FOREACH ($User IN $Script:ConfigData.GlobalUsers)
					{
						IF ($Script:GlobalUsers.Contains($User) -EQ $FALSE)
						{
							$Script:GlobalUsers += $User
						}
					}
				}

				RETURN $TRUE
			}
			CATCH
			{
				ReportToLog "THERE WAS A PROBLEM LOADING MAPPINGS"
			}
		}
	}

	RETURN $FALSE
}

FUNCTION Manage-AzureADConnection
{
	$ExistingAuth = $FALSE

	# Check connected to AzureAD
	$Script:ConnectedToAAD = Check-AzureADService

	IF ($Script:ConnectedToAAD -EQ $TRUE)
	{
		$ExistingAuth = $TRUE
		ReportToLog "Connected to Azure AD with existing authentication"
	}
	ELSE
	{
		IF ($Script:Connect -EQ $TRUE)
		{
			ReportToLog "Connecting to Azure AD"
			$AzureContext = $NULL
			$ConnErrorMSG = "UNKNOWN ERROR ENCOUNTERED CONNECTING TO AZURE AD"

			TRY
			{
				IF ($Script:Credentials -NE $NULL)
				{
					$ConnErrorMSG = "SUPPLIED CREDENTIALS WERE NOT CORRECT"

					$AzureContext =Connect-AzureAD -ErrorAction SilentlyContinue -Credential $Script:Credentials
				}
				ELSEIF ($Script:Username -NE "" -AND $Script:Password -NE "")
				{
					$ConnErrorMSG = "SUPPLIED CREDENTIALS WERE NOT CORRECT"
					$Script:Password = ConvertTo-SecureString -String $Script:Password -AsPlainText -Force
					$Script:Credentials = New-Object -Typename System.Management.Automation.PSCredential -ArgumentList $Script:Username, $Script:Password

					$AzureContext =Connect-AzureAD -ErrorAction SilentlyContinue -Credential $Script:Credentials
				}
				ELSEIF ($Script:Username -NE "")
				{
					$ConnErrorMSG = "CONNECTION TO AZURE AD CANCELLED BY USER"
					#Using triggering instead of prompting as it you can be both disconnected and still
					#Authenticated which would bypass to actual prompt and just connect you automatically
					ReportToLog "Triggering login for $($Script:Username)"

					$AzureContext =Connect-AzureAD -ErrorAction SilentlyContinue -AccountID $Script:Username
				}
				ELSE
				{
					$ConnErrorMSG = "CONNECTION TO AZURE AD CANCELLED BY USER"
					ReportToLog "Prompting user to login"

					$AzureContext =Connect-AzureAD -ErrorAction SilentlyContinue
				}

				$Script:ConnectedToAAD = $TRUE
				ReportToLog "Connected as: $($AzureContext.Account.ID)"
			}
			CATCH
			{
				#If any issues report error and return failure
				ReportToLog $ConnErrorMSG
				RETURN $FALSE
			}
		}
		ELSE
		{
			ReportToLog "NOT CONNECTED TO AZURE AD"
			ReportToLog "To manually connect run: Connect-AzureAD"
		}
	}

	IF ($Script:ConnectedToAAD -EQ $TRUE)
	{
		#Ensure we are connected to the correct AAD and return true if so
		$CorrectDomain = Check-AzureADDomain

		IF ($CorrectDomain -EQ $TRUE)
		{
			ReportToLog "Connected to correct Azure AD"

			RETURN $TRUE
		}
		ELSE
		{
			ReportToLog "NOT CONNECTED TO CORRECT AZURE AD"

			IF ($Script:Disconnect -EQ $TRUE)
			{
				Disconnect-AzureADService

				#If credentials supplied bail out or recursively try again
				IF ($Script:Credentials -NE $NULL)
				{
					IF ($ExistingAuth -EQ $TRUE)
					{
						RETURN Manage-AzureADConnection
					}
					ELSE
					{
						ReportToLog "SUPPLY DETAILS FOR CORRECT AZURE AD"
					}
				}
				ELSE
				{
					#This is just to clear username if supplied
					#Required to stop looping issue
					$Script:Username = ""

					RETURN Manage-AzureADConnection
				}

			}
			ELSE
			{
				ReportToLog "To manually disconnect run: Disconnect-AzureAD"
			}

		}
	}

	RETURN $FALSE
}

FUNCTION Load-AzureADObjects
{
	# Create Group Membership Hash Table
	ReportToLog "Getting AAD Group Memberships"
	$GroupList = Get-AzureADGroup

	FOREACH ($Group IN $GroupList)
	{
		ReportToLog "	Loading $($Group.DisplayName)"
		$Script:GroupDetails.Add($Group.DisplayName, $Group)
		$CurrentGroupMembers = Get-AzureADGroupMember -All $TRUE -ObjectId $Group.ObjectId
		#Get-AzureADGroupMember returns NULL and not an empty array when group has no members which breaks validation
		IF ($CurrentGroupMembers -EQ $NULL)
		{
			DebugOutput "		$($Group.DisplayName) is empty"
			$CurrentGroupMembers = @()
		}
		$Script:GroupMemberships.Add($Group.DisplayName, $CurrentGroupMembers)
	}

	# Create Group Membership Hash Table
	ReportToLog "Getting AAD User List"
	FOREACH ($User IN (Get-AzureADUser -All $TRUE))
	{
		$Script:UserDetails.Add($User.UserPrincipalName, $User)
	}
}

FUNCTION Validate-Mappings
{
	$RESULT = $TRUE

	ReportToLog "Validating Global Groups and Users"
	$GroupsValid = Validate-GroupList $Script:GlobalGroups
	$UsersValid = Validate-UserList $Script:GlobalUsers
	IF (-Not ($GroupsValid -AND $UsersValid))
	{
		$RESULT = $FALSE
	}

	ReportToLog "Validating Mappings"

	#Check each mapping
	FOREACH ($Mapping in $Script:GroupMappings.GetEnumerator())
	{
		ReportToLog "	Validating $($Mapping.Name)"
		$VALID = $TRUE

		#Check Parent value correct
		IF ($Script:GroupDetails[$Mapping.Name] -EQ $NULL)
		{
			ReportToLog "		- $($Mapping.Name) cannot be found"
			$VALID = $FALSE
		}

		#Check ChildGroups & ChildUsers valid
		$GroupsValid = Validate-GroupList $Mapping.Value["Groups"]
		$UsersValid = Validate-UserList $Mapping.Value["Users"]

		IF (-Not ($GroupsValid -AND $UsersValid))
		{
			$RESULT = $FALSE
		}
		ELSE
		{
			DebugOutput "		- Valid"
		}
	}

	IF ($RESULT -EQ $FALSE)
	{
		ReportToLog "Please fix mapping errors before continuing!"
	}

	RETURN $RESULT
}

FUNCTION Validate-GroupList ($GroupArray)
{
	$RESULT = $TRUE

	FOREACH ($GroupName IN $GroupArray)
	{
		IF ($Script:GroupDetails[$GroupName] -EQ $NULL)
		{
			ReportToLog "		- $GroupName cannot be found"
			$RESULT = $FALSE
		}
	}

	RETURN $RESULT
}

FUNCTION Validate-UserList ($UserArray)
{
	$RESULT = $TRUE

	FOREACH ($Script:Username IN $UserArray)
	{
		IF ($Script:UserDetails[$Script:Username] -EQ $NULL)
		{
			ReportToLog "		- $Script:Username cannot be found"
			$RESULT = $FALSE
		}
	}

	RETURN $RESULT
}

FUNCTION Memberships-Handle
{
	ReportToLog "Compiling Memberships"

	$OldMemberships = @{}
	$NewMemberships = @{}
	$MembershipChanges = @{}

	#Get the user lists
	FOREACH ($Mapping IN $Script:GroupMappings.GetEnumerator())
	{
		DebugOutput "	Processing $($Mapping.Name)"

		#Get the current memberships
		$OldMembershipArray = @()
		FOREACH ($Member IN $Script:GroupMemberships[$Mapping.Name])
		{
			$OldMembershipArray += $Member.UserPrincipalName
		}
		$OldMemberships[$Mapping.Name] = $OldMembershipArray

		#Generate what the memberships should be
		$NewMemberships[$Mapping.Name] = Memberships-Compile ($Mapping)
	}

	ReportToLog "Comparing Memberships"
	FOREACH ($NewMembershipArray IN $NewMemberships.GetEnumerator())
	{
		DebugOutput "	Comparing $($NewMembershipArray.Name)"

		$Changes = Memberships-Compare -NewMemberships $NewMembershipArray.Value -OldMemberships $OldMemberships[$NewMembershipArray.Name]

		IF ($Changes.Count -GT 0)
		{
			$MembershipChanges[$NewMembershipArray.Name] = $Changes
		}
	}

	IF ($MembershipChanges.Count -GT 0)
	{
		IF ($Script:Commit -LIKE "Prompt")
		{
			Memberships-OutputChanges $MembershipChanges

			Write-Host "Press [Y] To Makes Changes Or [N] To Cancel"

			IF (AwaitYesNoKeypress)
			{
				Memberships-Update $MembershipChanges
			}
			ELSE
			{
				ReportToLog "Memberships Were Not Updated"
			}
		}
		ELSEIF ($Script:Commit -LIKE "Yes")
		{
			Memberships-Update $MembershipChanges
		}
		ELSE
		{
			Memberships-OutputChanges $MembershipChanges
			ReportToLog "SET COMMIT TO YES OR PROMPT TO APPLY PENDING UPDATES"
		}
	}
	ELSE
	{
		ReportToLog "Memberships Do Not Need To Be Updated"
	}
}

FUNCTION Memberships-Compile ($Mapping)
{
	#Add our global groups and users first
	$GroupArray = $Script:GlobalGroups
	$NewMembersArray = $Script:GlobalUsers

	#Add our mapping groups to group array
	IF ($Mapping.Value["Groups"] -NE $NULL)
	{
		FOREACH ($Group IN $Mapping.Value["Groups"])
		{
			IF ($GroupArray.Contains($Group) -EQ $FALSE)
			{
				DebugOutput ("		$Group Mapped")
				$GroupArray += $Group
			}
		}
	}
	#Add our mapping users to members array
	IF ($Mapping.Value["Users"] -NE $NULL)
	{
		FOREACH ($User IN $Mapping.Value["Users"])
		{
			IF ($NewMembersArray.Contains($User) -EQ $FALSE)
			{
				DebugOutput ("		$User Mapped")
				$NewMembersArray += $User
			}
		}
	}

	$LOOP = $TRUE
	$i = 0

	#Let's get our loop on to flatten the groups array
	WHILE ($LOOP -EQ $TRUE)
	{
		#Get the next group in the array and move our counter
		$GroupName = $GroupArray[$i]
		$i++

		DebugOutput ("		Checking $GroupName")

		#For each item in the current group
		FOREACH ($Member in $Script:GroupMemberships[$GroupName])
		{
			DebugOutput ("			Member $($Member.DisplayName) is a $($Member.ObjectType)")
			#If user add to members array
			IF ($Member.ObjectType -LIKE "User")
			{
				#Only if not already in there though
				IF ($NewMembersArray.Contains($Member.UserPrincipalName) -EQ $FALSE)
				{
					$NewMembersArray += $Member.UserPrincipalName
					DebugOutput ("			- Adding $($Member.UserPrincipalName) to array")
				}
			}
			#If group add to groups array
			ELSEIF ($Member.ObjectType -LIKE "Group")
			{
				#Only if not already in there though
				IF ($GroupArray.Contains($Member.DisplayName) -EQ $FALSE)
				{
					$GroupArray += $Member.DisplayName
					DebugOutput ("			- Adding $($Member.DisplayName) to array")
				}
			}
		}

		DebugOutput ("		Completed $GroupName")

		#If our counter is at the end stop the loop
		IF ($i -EQ $GroupArray.Count)
		{
			$LOOP = $FALSE
		}
	}

	RETURN $NewMembersArray
}

FUNCTION Memberships-Compare
{
param
(
	[array] $NewMemberships,
	[array] $OldMemberships
)
	$Changes = @{}

	#Check which current members are not in new membership list
	FOREACH ($Member IN $OldMemberships)
	{
		IF ($NewMemberships.Contains($Member) -EQ $FALSE)
		{
			$Changes[$Member] = -1

			IF ($Script:Commit -NOTLIKE "Yes")
			{
				DebugOutput "			? Remove $Member"
			}
		}
	}

	#Check which new members are not in existing membership list
	FOREACH ($Member IN $NewMemberships)
	{
		IF ($OldMemberships.Contains($Member) -EQ $FALSE)
		{
			$Changes[$Member] = 1

			IF ($Script:Commit -NOTLIKE "Yes")
			{
				DebugOutput "			? Add $Member"
			}
		}
	}

	RETURN $Changes
}

FUNCTION Memberships-OutputChanges ($Changes)
{
	ReportToLog "Pending Membership Changes"
	FOREACH ($ChangeArray IN $Changes.GetEnumerator())
	{
		ReportToLog "	$($ChangeArray.Name)"

		FOREACH ($Change IN $ChangeArray.Value.GetEnumerator())
		{
			IF ($Change.Value -EQ 1)
			{
				ReportToLog "		? Add $($Change.Name)"
			}
			ELSEIF ($Change.Value -EQ -1)
			{
				ReportToLog "		? Remove $($Change.Name)"
			}
		}
	}
}

FUNCTION Memberships-Update ($Changes)
{
	ReportToLog "Updating Memberships"
	FOREACH ($ChangeArray IN $Changes.GetEnumerator())
	{
		ReportToLog "	$($ChangeArray.Name)"

		FOREACH ($Change IN $ChangeArray.Value.GetEnumerator())
		{
			IF ($Change.Value -EQ 1)
			{
				Add-AzureADGroupMember -ObjectId $Script:GroupDetails[$ChangeArray.Name].ObjectID -RefObjectId $Script:UserDetails[$Change.Name].ObjectID
				ReportToLog "		+ Added $($Change.Name)"
			}
			ELSEIF ($Change.Value -EQ -1)
			{
				Remove-AzureADGroupMember -ObjectId $Script:GroupDetails[$ChangeArray.Name].ObjectID -MemberId $Script:UserDetails[$Change.Name].ObjectID
				ReportToLog "		- Removed $($Change.Name)"
			}
		}
	}
}

<# ---------------------------------
	AZUREAD HELPER FUNCTIONS
--------------------------------- #>

FUNCTION Check-AzureADModule
{
	$ModuleProbe = Get-InstalledModule | Where-Object {$_.Name -eq "AzureAD" -OR $_.Name -eq "AzureADPreview"}

	IF ($ModuleProbe -NE $NULL)
	{
		RETURN $TRUE
	}

	RETURN $FALSE
}

FUNCTION Check-AzureADService
{
	TRY
	{
		$Quiet = Get-AzureADDomain -ErrorAction SilentlyContinue
		RETURN $TRUE
	}
	CATCH { <# Nothing #> }

	RETURN $FALSE
}

#Just for consistency
FUNCTION Disconnect-AzureADService
{
	ReportToLog "Disconnecting from Azure AD"
	Disconnect-AzureAD
}

FUNCTION Check-AzureADDomain
{
	$Domains = Get-AzureADDomain -ErrorAction SilentlyContinue

	$TenantDomain = "$($Script:ConfigData.TenantPrefix).onmicrosoft.com"

	DebugOutput "Checking for tenant domain: $TenantDomain"
	IF ($?)
	{
		ForEach ($Domain IN $Domains)
		{
			IF ($Domain.Name -IEQ $TenantDomain)
			{
				RETURN $TRUE
			}
		}
	}

	RETURN $FALSE
}


<# ---------------------------------
	GENERIC HELPER FUNCTIONS
--------------------------------- #>

FUNCTION GetFilename
{
param
(
	[string] $Extension
)
	#Get the full path of our script
	$ScriptPath = $MyInvocation.ScriptName

	#Split it by folder seperators
	$ScriptPathSplit = $ScriptPath.Split("\")

	#Grab just filename at the end
	$ScriptNameSplit = $ScriptPathSplit[$ScriptPathSplit.Count -1].Split(".")

	#Remove the extention from the end and concatinate
	$ScriptName = $ScriptNameSplit[0..($ScriptNameSplit.Count - 2)]

	#Return filename
	RETURN "$ScriptName.$Extension"
}

FUNCTION AwaitYesNoKeypress
{
	$KeyPress = $NULL
	DO
	{
		IF ($KeyPress.Character -eq 'y')
		{
			RETURN $TRUE
		}
		ELSEIF ($KeyPress.Character -eq 'n')
		{
			RETURN $FALSE
		}
	}
	WHILE ($KeyPress = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyUp'))
}

FUNCTION DebugOutput ($DebugInfo)
{
	IF ($Script:Debug -EQ $TRUE) { Write-Host $DebugInfo }
}

FUNCTION ReportToLog ($EventDetails)
{
	IF ($Script:LogFile -NE "")
	{
		Write-Host $EventDetails

		IF (Test-Path $Script:LogFile)
		{
			Out-File -FilePath $Script:LogFile -InputObject $EventDetails -Append
		}
		ELSE
		{
			Out-File -FilePath $Script:LogFile -InputObject $EventDetails
		}

	}
	ELSE
	{
		Write-Host "Log file not specified`n"
	}
}

#Start our scipt
Main