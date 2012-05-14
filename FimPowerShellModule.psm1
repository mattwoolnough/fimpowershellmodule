﻿###
### Load the FIMAutomation Snap-In
###
if(-not (get-pssnapin | Where-Object {$_.Name -eq 'FIMAutomation'})) {add-pssnapin FIMAutomation}

function New-FimImportObject
{
<#
	.SYNOPSIS 
	Creates a new ImportObject for the FIM Configuration Migration Cmdlets

	.DESCRIPTION
	The New-FimImportObject function makes it easier to use Import-FimConfig by providing an easier way to create ImportObject objects.
	This makes it easier to perform CRUD operations in the FIM Service.
   
	.OUTPUTS
 	the FIM ImportObject is returned by this function.  The next logical step is take this output and feed it to Import-FimConfig.
   
   	.EXAMPLE
	PS C:\$createRequest = New-FimImportObject -ObjectType Person -State Create -Changes @{
		AccountName='Bob' 
		DisplayName='Bob the Builder'
		}
	PS C:\$createRequest | Import-FIMConfig
	
	DESCRIPTION
	-----------
   	Creates an ImportObject for creating a new Person object with AccountName and DisplayName.
	The above sample uses a hashtable for the Changes parameter.
	
	.EXAMPLE
	PS C:\$createRequest = New-FimImportObject -ObjectType Person -State Create -Changes @(
		New-FimImportChange -Operation None -AttributeName 'Bob' -AttributeValue 'foobar' 
		New-FimImportChange -Operation None -AttributeName 'DisplayName' -AttributeValue 'Bob the Builder'  )
	PS C:\$createRequest | Import-FIMConfig
	
	DESCRIPTION
	-----------
   	Creates an ImportObject for creating a new Person object with AccountName and DisplayName.
	The above sample uses an array of ImportChange objects for the Changes parameter.
	
	NOTE: the attribute 'Operation' type of 'None' works when the object 'State' is set to 'Create'.
	
	.EXAMPLE
	PS C:\$updateRequest = New-FimImportObject -ObjectType Person -State Put -AnchorPairs @{AccountName='Bob'} -Changes @(
		New-FimImportChange -Operation Replace -AttributeName 'FirstName' -AttributeValue 'Bob' 
		New-FimImportChange -Operation Replace -AttributeName 'LastName' -AttributeValue 'TheBuilder'  )
	PS C:\$updateRequest | Import-FIMConfig
	
	DESCRIPTION
	-----------
   	Creates an ImportObject for updating an existing Person object with FirstName and LastName.

	.EXAMPLE
	PS C:\$deleteRequest = New-FimImportObject -ObjectType Person -State Delete -AnchorPairs @{AccountName='Bob'} 
	PS C:\$deleteRequest | Import-FIMConfig
	
	DESCRIPTION
	-----------
   	Creates an ImportObject for deleting an existing Person object.	
#>
	param
	( 
	<#
	.PARAMETER ObjectType
	The object type for the target object.
	NOTE: this is case sensitive
	NOTE: this is the ResourceType's 'name' attribute, which often does NOT match what is seen in the FIM Portal.
	#>
	[parameter(Mandatory=$true)] 
	[String]
	$ObjectType,

	<#
	.PARAMETER State
	The operation to perform on the target, must be one of:
	-Create
	-Put
	-Delete
	-Resolve
	-None
	#>
	[parameter(Mandatory=$true)]
	[String]
	[ValidateScript({(“Create”, “Put”, “Delete”, "Resolve", "None") -icontains $_})]
	$State,

	<#
	.PARAMETER AnchorPairs
 	A name:value pair used to find a target object for Put, Delete and Resolve operations.  The AchorPairs is used in conjunction with the ObjectType by the FIM Import-FimConfig cmdlet to find the target object.
	#>
	[parameter(Mandatory=$false)] 
	[ValidateScript({$_ -is [Hashtable] -or $_ -is [Microsoft.ResourceManagement.Automation.ObjectModel.JoinPair[]] -or $_ -is [Microsoft.ResourceManagement.Automation.ObjectModel.JoinPair]})]
	$AnchorPairs,

	<#	
	.PARAMETER SourceObjectIdentifier
	Not intelligently used or tested yet...  
	#>
	[parameter(Mandatory=$false)] 
	$SourceObjectIdentifier = [Guid]::Empty,

	<#
	.PARAMETER TargetObjectIdentifier
 	The ObjectID of the object to operate on.
	Defaults to an empty GUID
	#>
	[parameter(Mandatory=$false)] 
	$TargetObjectIdentifier = [Guid]::Empty,

	<#
	.PARAMETER Changes
	The changes to make to the target object.  This parameter accepts a Hashtable or FIM ImportChange objects as input. If a Hashtable is supplied as input then it will be converted into FIM ImportChange objects.  You're welcome.
	#>
	[parameter(Mandatory=$false)]
	[ValidateScript({($_ -is [Array] -and $_[0] -is [Microsoft.ResourceManagement.Automation.ObjectModel.ImportChange]) -or $_ -is [Hashtable] -or $_ -is [Microsoft.ResourceManagement.Automation.ObjectModel.ImportChange]})]
	$Changes,
	
	<#
	.PARAMETER ApplyNow
	When specified, will sumit the request to FIM
	#>
	[Switch]
	$ApplyNow = $false,
	
	<#
	.PARAMETER PassThru
	When specified, will return the ImportObject as output
	#>
	[Switch]
	$PassThru = $false,    
    
    <#
	.PARAMETER SkipDuplicateCheck
	When specified, will skip the duplicate create request check
	#>
	[Switch]
	$SkipDuplicateCheck = $false
    		
	) 
	end
	{
       $importObject = New-Object Microsoft.ResourceManagement.Automation.ObjectModel.ImportObject
        $importObject.SourceObjectIdentifier = $SourceObjectIdentifier
        $importObject.TargetObjectIdentifier = $TargetObjectIdentifier
        $importObject.ObjectType = $ObjectType
        $importObject.State = $State
        
        ###
        ### Process the Changes parameter
        ###
        if ($Changes -is [Hashtable])
        {
            $Changes.GetEnumerator() | 
            ForEach{
                $importObject.Changes += New-FimImportChange -AttributeName $_.Key -AttributeValue $_.Value -Operation Replace
            }        
        }
        else
        {
            $importObject.Changes = $Changes
        }
        
        ###
        ### Handle Reslove and Join Pairs
        ###
        if ($AnchorPairs)
        {
            if ($AnchorPairs -is [Microsoft.ResourceManagement.Automation.ObjectModel.JoinPair[]] -or $AnchorPairs -is [Microsoft.ResourceManagement.Automation.ObjectModel.JoinPair])
            {
                $importObject.AnchorPairs = $AnchorPairs
            }
            else
            {
                $AnchorPairs.GetEnumerator() | 
                ForEach{
                    $anchorPair = New-Object Microsoft.ResourceManagement.Automation.ObjectModel.JoinPair
                    $anchorPair.AttributeName = $_.Key
                    $anchorPair.AttributeValue = $_.Value
                    $importObject.AnchorPairs += $anchorPair
                }        
            }    
        }
        
        ###
        ### Handle Put and Delete
        ###
        if (($State -ieq 'Put' -or $State -ieq 'Delete') -and $importObject.AnchorPairs.Count -eq 1)
        {
			$targetID = Get-FimObjectID -ObjectType $ObjectType -AttributeName @($importObject.AnchorPairs)[0].AttributeName -AttributeValue @($importObject.AnchorPairs)[0].AttributeValue
            
			$importObject.TargetObjectIdentifier = $targetID
        }     
       
        ###
        ### Handle Duplicate Values on a Put request
        ###
        if ($State -ieq 'Put')# -and $Operation -ieq 'Add')
        {
            ### Get the Target object
            $currentFimObject = Export-FIMConfig -OnlyBaseResources -CustomConfig ("/*[ObjectID='{0}']" -F $importObject.TargetObjectIdentifier) | Convert-FimExportToPSObject
            
          ### Create a new array containing only valid ADDs
            [Array]$uniqueImportChanges = $importObject.Changes | Where-Object {$_.Operation -ne 'Add'}
            $importObject.Changes | 
                Where-Object {$_.Operation -eq 'Add'} |
                ForEach-Object {
                    Write-Verbose ("Checking to see if attribute '{0}' already has a value of '{1}'" -F $_.AttributeName, $_.AttributeValue)
                    if ($currentFimObject.($_.AttributeName) -eq $_.AttributeValue)
                    {
                        Write-Warning ("Duplicate attribute found: '{0}' '{1}'" -F $_.AttributeName, $_.AttributeValue)
                    }
                    else
                    {
                        $uniqueImportChanges += $_
                    }
                }
            ### Replace the Changes array with our validated array
            $importObject.Changes = $uniqueImportChanges
            $importObject.Changes = $importObject.Changes | Where {$_ -ne $null}
            
            if (-not ($importObject.Changes))
            {
                Write-Warning "No changes left on this Put request."
            }
        }
        
        if ($ApplyNow -eq $true)
        {
            if ($SkipDuplicateCheck)
            {
                $importObject | Import-FIMConfig 
                
            }
            else
            {
                $importObject | Skip-DuplicateCreateRequest | Import-FIMConfig
                
            } 
        }
        
        if ($PassThru -eq $true)
        {
            Write-Output $importObject
        }     
	}
}

Function New-FimImportChange
{
    Param
    (                              
        [parameter(Mandatory=$true)] 
		[String]
        $AttributeName,
        
        [parameter(Mandatory=$true)] 
		[ValidateScript({($_ -is [Array] -and $_.Count -eq 3) -or $_ -is [String]})]
        $AttributeValue,
		
		[parameter(Mandatory=$true)]
		[ValidateScript({(“Add”, “Replace”, “Delete”, "None") -icontains $_})]
        $Operation,
		
		[parameter(Mandatory=$false)]  
		[Boolean]
        $FullyResolved = $true,
        
        [parameter(Mandatory=$false)]  
		[String]
        $Locale = "Invariant"
    ) 
    END
    {
        $importChange = New-Object Microsoft.ResourceManagement.Automation.ObjectModel.ImportChange
        $importChange.Operation = $Operation
        $importChange.AttributeName = $AttributeName
        $importChange.FullyResolved = $FullyResolved
        $importChange.Locale = $Locale
        
        ###
        ### Process the AttributeValue Parameter
        ###
        if ($AttributeValue -is [String])
        {
            $importChange.AttributeValue = $AttributeValue
        }
        elseif ($AttributeValue -is [Array])
        {
            ###
            ### Resolve Resolve Resolve
            ###
            if ($AttributeValue.Count -ne 3)
            {
                Write-Error "For the 'Resolve' option to work, the AttributeValue parameter requires 3 values in this order: ObjectType, AttributeName, AttributeValue"
            }
			$objectId = Get-FimObjectID -ObjectType $AttributeValue[0] -AttributeName $AttributeValue[1] -AttributeValue $AttributeValue[2]
            
			if (-not $objectId)
            {
                Throw (@"
                FIM Resolve operation failed for: {0}:{1}:{2}
                Could not find an object of type '{0}' with an attribute '{1}' value equal to '{2}'
"@ -F $AttributeValue[0],$AttributeValue[1],$AttributeValue[2])
            }
            else
            {
				$importChange.AttributeValue = $objectId              
            }            
        }
        $importChange
    }
}

Function Skip-DuplicateCreateRequest
{
<#
	.SYNOPSIS 
	Detects a duplicate 'Create' request then removes it from the pipeline

	.DESCRIPTION
	The Skip-DuplicateCreateRequest function makes it easier to use Import-FimConfig by providing preventing a duplicate Create request.
	In most cases FIM allows the creation of duplicate objects since it mostly does not enforce uniqueness.  When loading configuration objects this can easily lead to the accidental duplication of MPRs, Sets, Workflows, etc.	

	.PARAMETER ObjectType
	The object type for the target object.
	NOTE: this is case sensitive
	NOTE: this is the ResourceType's 'name' attribute, which often does NOT match what is seen in the FIM Portal.
   
	.OUTPUTS
 	the FIM ImportObject is returned by this function ONLY if a duplicate was not fount.
   
   	.EXAMPLE
	PS C:\$createRequest = New-FimImportObject -ObjectType Person -State Create -Changes @{
		AccountName='Bob' 
		DisplayName='Bob the Builder'
		}
	PS C:\$createRequest | Skip-DuplicateCreateRequest | Import-FIMConfig
	
	DESCRIPTION
	-----------
   	Creates an ImportObject for creating a new Person object with AccountName and DisplayName.
	If an object with the DisplayName 'Bob the Builder' already exists, then a warning will be displayed, and no input will be provided to Import-FimConfig because the Skip-DuplicateCreateRequest would have filtered it from the pipeline.
#>
   	Param
    ( 
		<#
		AnchorAttributeName is used to detect the duplicate in the FIM Service.  It defaults to the 'DisplayName' attribute.		
		#>
        [parameter(Mandatory=$true, ValueFromPipeline = $true)]        
        $ImportObject,
        [String]
        $AnchorAttributeName = 'DisplayName'
    )
    Process
    {
        if ($ImportObject.State -ine 'Create')
        {
            Write-Output $ImportObject
            return
        }
        
        $anchorAttributeValue = $ImportObject.Changes | where {$_.AttributeName -eq $AnchorAttributeName} | select -ExpandProperty AttributeValue
        
		###
		### If the anchor attribute is not present on the ImportObject, then we can't detect a duplicate
		### Behavior in this case is to NOT filter
		###
        if (-not $anchorAttributeValue)
        {
            Write-Warning "Skipping duplicate detection for this Create Request because we do not have an anchor attribute to search with."
            Write-Output $ImportObject
            return
        }
        
        $objectId = Get-FimObjectID -ObjectType $ImportObject.ObjectType -AttributeName $AnchorAttributeName -AttributeValue $anchorAttributeValue -ErrorAction SilentlyContinue
            
		if ($objectId)
        {
            ### This DID resolve to an object on the target system
            ### so it is NOT safe to create
            ### do NOT put the object back on the pipeline
            Write-Warning "An object matches this object in the target system, so skipping the Create request"
        } 
        else
        {
            ### This did NOT resolve to an object on the target system
            ### so it is safe to create
            ### put the object back on the pipeline
            Write-Output $ImportObject     
        }
     }
}

Function Wait-FimRequest
{
   	Param
    ( 
        [parameter(Mandatory=$true, ValueFromPipeline = $true)]
        [Microsoft.ResourceManagement.Automation.ObjectModel.ImportObject]
        [ValidateScript({$_.TargetObjectIdentifier -like "urn:uuid:*"})]
        $ImportObject,
        
        [parameter(Mandatory=$false)]
        $RefreshIntervalInSeconds = 5   
    )
    Process
    { 
        ###
    	### Loop while the Request.RequestStatus is not any of the Final status values
        ###
    	Do{
            ###
            ### Get the FIM Request object by querying for a Request by Target
            ###
            $xpathFilter = @" 
                /Request 
                    [ 
                        Target='{0}'
                        and RequestStatus != 'Denied' 
                        and RequestStatus != 'Failed' 
                        and RequestStatus != 'Canceled' 
                        and RequestStatus != 'CanceledPostProcessing' 
                        and RequestStatus != 'PostProcessingError' 
                        and RequestStatus != 'Completed' 
                    ] 
"@ -F $ImportObject.TargetObjectIdentifier.Replace('urn:uuid:','')
            
    	    $requests = Export-FIMConfig -OnlyBaseResources -CustomConfig $xpathFilter
    	    
    	    if ($requests -ne $null)
    	    {
    	        Write-Verbose ("Number of pending requests: {0}" -F $requests.Count)
    	        Start-Sleep -Seconds $RefreshIntervalInSeconds
    	    }
    	} 
    	While ($requests -ne $null)
    } 
}

Function Convert-FimExportToPSObject
{
    Param
    (
        [parameter(Mandatory=$true, ValueFromPipeline = $true)]
        [Microsoft.ResourceManagement.Automation.ObjectModel.ExportObject]
        $ExportObject
    )
    Process
    {        
        $psObject = New-Object PSObject
        $ExportObject.ResourceManagementObject.ResourceManagementAttributes | ForEach-Object{
            if ($_.Value -ne $null)
            {
                $value = $_.Value
            }
            elseif($_.Values -ne $null)
            {
                $value = $_.Values
            }
            else
            {
                $value = $null
            }
            $psObject | Add-Member -MemberType NoteProperty -Name $_.AttributeName -Value $value
        }
        Write-Output $psObject
    }
}

Function Get-FimObjectID
{
   	Param
    (       
        $ObjectType,
		
        [parameter(Mandatory=$true)]
        [String]
        $AttributeName = 'DisplayName',
		
        [parameter(Mandatory=$true)]
        [alias(“searchValue”)]
        [String]
        $AttributeValue
    )
    Process
    {   
		$resolver = New-Object Microsoft.ResourceManagement.Automation.ObjectModel.ImportObject
        $resolver.SourceObjectIdentifier = [Guid]::Empty
        $resolver.TargetObjectIdentifier = [Guid]::Empty
        $resolver.ObjectType 			 = $ObjectType
        $resolver.State 				 = 'Resolve'
		
        $anchorPair = New-Object Microsoft.ResourceManagement.Automation.ObjectModel.JoinPair
        $anchorPair.AttributeName  = $AttributeName
        $anchorPair.AttributeValue = $AttributeValue
                    
        $resolver.AnchorPairs = $anchorPair
        
        try
        {
            Import-FIMConfig $resolver -ErrorAction Stop | Out-Null
     
            if ($resolver.TargetObjectIdentifier -eq [Guid]::Empty)
            {
                ### This did NOT resolve to an object on the target system
                Write-Error ("An object was not found with this criteria: {0}:{1}:{2}"   -F  $ObjectType, $AttributeName,  $AttributeValue)
            }
            else
            {
                ### This DID resolve to an object on the target system
                Write-Output ($resolver.TargetObjectIdentifier -replace 'urn:uuid:')
            }         
        }
        catch
        {
            if ($_.Exception.Message -ilike '*the target system returned no matching object*')
            {
                ### This did NOT resolve to an object on the target system
                Write-Error ("An object was not found with this criteria: {0}:{1}:{2}"   -F  $ObjectType, $AttributeName,  $AttributeValue)
            }
            elseif ($_.Exception.Message -ilike '*cannot filter as requested*')
            {
                ### This is a bug in Import-FIMConfig whereby it does not escape single quotes in the XPath filter
                ### Try again using Export-FIMConfig
                $exportResult = Export-FIMConfig -OnlyBaseResources -CustomConfig ("/{0}[{1}=`"{2}`"]" -F $resolver.ObjectType, $resolver.AnchorPairs[0].AttributeName, $resolver.AnchorPairs[0].AttributeValue ) -ErrorAction SilentlyContinue
                
                if ($exportResult -eq $null)
                {
                    Write-Error ("An object was not found with this criteria: {0}:{1}:{2}"   -F  $ObjectType, $AttributeName,  $AttributeValue)
                }
                else
                {
                    Write-Output ($exportResult.ResourceManagementObject.ObjectIdentifier -replace 'urn:uuid:' )
                }            
            }
            else
            {
               Write-Error ("Import-FimConfig produced an error while resolving this object in the target system{0}" -F $_.Exception.Message)       
            } 
        }
    }
}

function Get-ObjectSid
{
<#
.SYNOPSIS 
Gets the ObjectSID as Base64 Encoded String

.DESCRIPTION
GetSidAsBase64 tries to find the object, then translate it into a Base64 encoded string

.OUTPUTS
a string containing the Base64 encoded ObjectSID

.EXAMPLE
Get-ObjectSid -AccountName v-crmart -Verbose

OUTPUT
------
VERBOSE: Finding the SID for account: v-crmart
AQUAAAXXXAUVAAAAoGXPfnyLm1/nfIdwyoM6AA==  
	
DESCRIPTION
-----------
Gets the objectSID for 'v-crmart'
Does not supply a value for Domain

.EXAMPLE
Get-ObjectSid -AccountName v-crmart -Domain Redmond -Verbose

OUTPUT
------
VERBOSE: Finding the SID for account: Redmond\v-crmart
AQUAAAXXXAUVAAAAoGXPfnyLm1/nfIdwyoM6AA==  
	
DESCRIPTION
-----------
Gets the objectSID for 'v-crmart'
Does not supply a value for Domain
#>
   	param
    ( 
		<#
		A String containing the SamAccountName
		#>
        [parameter(Mandatory=$true)]
		[String]		
        $AccountName,
		<#
		A String containing the NetBIOS Domain Name
		#>		
        [parameter(Mandatory=$false)]
        [String]
        $Domain
	)
   	END
    {
		###
		### Construct the Account 
		###
		if ([String]::IsNullOrEmpty($Domain))
		{
			$account = $AccountName
		}
		else
		{
			$account = "{0}\{1}" -f $Domain, $AccountName
		}
		
        Write-Verbose "Finding the SID for account: $account"
		###
		### Get the ObjectSID
		###
		$ntaccount = New-Object System.Security.Principal.NTAccount $account
		try
		{
		    $binarySid = $ntaccount.Translate([System.Security.Principal.SecurityIdentifier]) 
		}
		catch
		{    
		    Throw @"
		Account could not be resolved to a SecurityIdentifier
"@  
		}
		
		$bytes = new-object System.Byte[] -argumentList $binarySid.BinaryLength
		$binarySid.GetBinaryForm($bytes, 0)
		$stringSid = [System.Convert]::ToBase64String($bytes)

		Write-Output $stringSid
    }
}

function Get-FimRequestParameter
{
<#
	.SYNOPSIS 
	Gets a RequestParameter from a FIM Request into a PSObject

	.DESCRIPTION
	The Get-FimRequestParameter function makes it easier to view FIM Request Parameters by converting them from XML into PSObjects
	This makes it easier view the details for reporting, and for turning a FIM Request back into a new FIM Request to repro fubars
   
	.OUTPUTS
 	a PSObject with the following properties:
		1. PropertyName
		2. Value
		3. Operation
   
   	.EXAMPLE
	$request = Export-FIMConfig -only -CustomConfig ("/Request[TargetObjectType = 'Person']") | 
    	Select -First 1 |
    	Convert-FimExportToPSObject |
		Get-FimRequestParameter
	
		OUTPUT
		------
		Value                                PropertyName                            Operation
		-----                                ------------                            ---------
		HoofHearted                          AccountName                             Create   
		HoofHearted                          DisplayName                             Create   
		Hoof                                 FirstName                               Create   
		Hearted                              LastName                                Create   
		Person                               ObjectType                              Create   
		4ba58a6e-5953-4c03-af83-7dbfb94691d4 ObjectID                                Create   
		7fb2b853-24f0-4498-9534-4e10589723c4 Creator                                 Create   
		
		DESCRIPTION
		-----------
		Gets one Request object from FIM, converts it to a PSOBject
#>
   	param
    ( 
		<#
		A String containing the FIM RequestParameter XML
        or
        A PSObject containing the RequestParameter property
		#>
        [parameter(Mandatory=$true, ValueFromPipeline = $true)]
        [ValidateScript({
		($_ -is [String] -and $_ -like "<RequestParameter*") `
		-or  `
		($_ -is [PSObject] -and $_.RequestParameter)})]
        $RequestParameter
    )
    process
    { 
        ### If the input is a PSObject then get just the RequestParameter property
        if ($RequestParameter -is [PSObject])
        {
            $RequestParameter = $RequestParameter.RequestParameter
        }
        
        $RequestParameter | foreach-Object{
            New-Object PSObject -Property @{
                PropertyName = ([xml]$_).RequestParameter.PropertyName
                Value = ([xml]$_).RequestParameter.Value.'#text'
                Operation = ([xml]$_).RequestParameter.Operation
            } | 
            Write-Output
        }
    }
}

Function New-FimSynchronizationRule
{
   	param
    (
        $DisplayName,
        $Description,
		$ManagementAgentID,
		$ConnectedObjectType,
		$ILMObjectType,
		$DisconnectConnectedSystemObject,
		$CreateConnectedSystemObject,
		$CreateILMObject,
		$FlowType,
		$Precedence,
		$ConnectedSystemScope,
		$RelationshipCriteria,
        $SynchronizationRuleParameters,
        $msidmOutboundIsFilterBased,
        $msidmOutboundScopingFilters,
		$PersistentFlow =  @(),
		$InitialFlow =  @()
    )
    $srImportObject = New-FimImportObject -ObjectType SynchronizationRule -State Create -Changes @{
	    DisplayName 						= $DisplayName
	    Description 						= $Description
	    ManagementAgentID 					= $ManagementAgentID
		ConnectedObjectType 				= $ConnectedObjectType
	    ILMObjectType 						= $ILMObjectType
		DisconnectConnectedSystemObject 	= $DisconnectConnectedSystemObject	
		CreateConnectedSystemObject 		= $CreateConnectedSystemObject
		CreateILMObject 					= $CreateILMObject	
		FlowType 							= $FlowType
		Precedence 							= $Precedence
		RelationshipCriteria 				= $RelationshipCriteria
    } -PassThru
    
    if ($msidmOutboundIsFilterBased)
    {
        $srImportObject.Changes += New-FimImportChange -AttributeName msidmOutboundIsFilterBased  -Operation None -AttributeValue $msidmOutboundIsFilterBased
        $srImportObject.Changes += New-FimImportChange -AttributeName msidmOutboundScopingFilters -Operation None -AttributeValue $msidmOutboundScopingFilters
    }
    
    if ($SynchronizationRuleParameters)
     {
        $srImportObject.Changes += New-FimImportChange -AttributeName SynchronizationRuleParameters -Operation Add -AttributeValue $SynchronizationRuleParameters
    }  
    
    if ($ConnectedSystemScope)
    {
        $srImportObject.Changes += New-FimImportChange -AttributeName ConnectedSystemScope -Operation Add -AttributeValue $ConnectedSystemScope
    }  
	
	$PersistentFlow | ForEach-Object {
		$srImportObject.Changes += New-FimImportChange -AttributeName PersistentFlow -Operation Add -AttributeValue $_
	}
    
    $InitialFlow | ForEach-Object {
		$srImportObject.Changes += New-FimImportChange -AttributeName InitialFlow -Operation Add -AttributeValue $_
	}
	
	$srImportObject | Skip-DuplicateCreateRequest | Import-FIMConfig
}