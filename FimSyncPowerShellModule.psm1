
Function Get-ManagementAgent
{
<#
   .SYNOPSIS 
   Gets the Management Agents from a Sync Server 

   .DESCRIPTION
   The Get-ManagementAgent function uses the MIIS WMI class to get the management agent   

   .PARAMETER ManagementAgentName
   Specifies the name of the MA to be retrieved.   

   .OUTPUTS
   The WMI object containing the management agent
   
   	.EXAMPLE
   	Get-ManagementAgent -Verbose -ManagementAgent ([GUID]'C19E29D8-FD3C-4A44-9E80-BCF5924FE26B')
	
	.EXAMPLE
	Get-ManagementAgent -Verbose -ManagementAgent C19E29D8-FD3C-4A44-9E80-BCF5924FE26B
	
	.EXAMPLE
	Get-ManagementAgent -Verbose -ManagementAgent CORP_AD
	
	.EXAMPLE
	Get-ManagementAgent -Verbose
#>
  Param
    (        
        [parameter(Mandatory=$false)] 
		[alias(“ManagementAgentName”)]
        $ManagementAgent	
    ) 
    End    
    {
		###
		### If MA is not supplied, return all MAs
		### Otherwise find the MA based on the type of input
		###		
		if (-not $ManagementAgent)
		{
			Get-WmiObject -Class MIIS_ManagementAgent -Namespace root/MicrosoftIdentityIntegrationServer
		}
		elseif($ManagementAgent -is [String])
		{     
			###
			### somebody might give us a GUID string as input, so try to convert the string to a GUID
			###
            $maGuid = $ManagementAgent -as [GUID]
            if ($maGuid)
            {
                Write-Verbose ("Using the supplied STRING converted to a GUID to get the MA: {0}" -F $ManagementAgent)
                Get-WmiObject -Class MIIS_ManagementAgent -Namespace root/MicrosoftIdentityIntegrationServer -Filter ("Guid='{0}'" -F $maGuid.ToString('b'))
            }
            else
            {
                Write-Verbose ("Using the supplied STRING to get the MA: {0}" -F $ManagementAgent)
                Get-WmiObject -Class MIIS_ManagementAgent -Namespace root/MicrosoftIdentityIntegrationServer -Filter ("Name='$ManagementAgent'")
            }			
		}
        elseif($ManagementAgent -is [Guid])
        {
            Write-Verbose ("Using the supplied GUID to get the MA: {0}" -F $ManagementAgent.ToString('b'))
            Get-WmiObject -Class MIIS_ManagementAgent -Namespace root/MicrosoftIdentityIntegrationServer -Filter ("Guid='{0}'" -F $ManagementAgent.ToString('b'))
        }
        else
        {
            Throw ("Unable to get a management agent with this input: {0} of this type {1}" -F $ManagementAgent, $ManagementAgent.GetType())
        }
    }
}

Function Get-ManagementAgentCounts
{
<#
   .SYNOPSIS 
   Gets the Num* Counters of a Management Agent 

   .DESCRIPTION
   The Get-ManagementAgentCounts function uses the Get-Member cmdlet to find all of the Num* methods on the MA
   It then executes them all and returns a new object that has all the counts

   .PARAMETER ManagementAgent
   Specifies the MA for which the counts will be collected
   This can either be the MA name as [String]
   or the WMI object using the MicrosoftIdentityIntegrationServer:MIIS_ManagementAgent class

   .OUTPUTS
   a new PSObject containing all of the counts
#>
   Param
    (        
        [parameter(Mandatory=$true, ValueFromPipeline = $true)]              
        $ManagementAgent
    ) 
	
	if ($ManagementAgent -is [System.Management.ManagementObject])
	{
		$MAGuid = $ManagementAgent.Guid
		$MAName = $ManagementAgent.Name
	}
	elseif($ManagementAgent -is [String])
	{
		$wmiMA = [wmi]"root\MicrosoftIdentityIntegrationServer:MIIS_ManagementAgent.Name='$ManagementAgent'"
		$MAGuid = $wmiMA.Guid
		$MAName = $wmiMA.Name
	}		
	
	$ma = Get-ManagementAgent $MAName
	$maCounts = New-Object PSObject 
	foreach ($method in $ma | Get-Member -MemberType Method | Where-Object {$_.Name -Like "Num*"} | Select-Object -ExpandProperty Name)
	{
	    $maCounts | 
	        Add-Member -MemberType noteproperty -name $method -value `
	        (
	            $ma | % {$_.$method.Invoke() } | 
	            Select-Object -ExpandProperty ReturnValue
	        )
	}
	$maCounts
}

function Get-MIIS_CSObject
{  
<#
   	.SYNOPSIS 
   	Gets the a CSObject using WMI 

   	.DESCRIPTION
   	The Get-MIIS_CSObject function uses the Get-WmiObject cmdlet to query for a MIIS_CSObject in FIM Sync.
   	MSDN has good documentation for MIIS_CSObject:
   	http://msdn.microsoft.com/en-us/library/windows/desktop/ms697741(v=vs.85).aspx

   	.OUTPUTS
   	the MIIS_CSObject returned by WMI
   	If searching by MVGuid, there may be multiple CSObjects returned because an MVObject can have multiple CSObjects joined to it
   
   	.EXAMPLE
   	Get-MIIS_CSObject -Account HoofHearted -Domain Litware -Verbose
	
	.EXAMPLE
   	Get-MIIS_CSObject -ManagementAgent Litware -DN 'CN=HoofHearted,OU=IceMelted,DC=Litware,DC=ca'
   
   	.EXAMPLE
   	Get-MIIS_CSObject -MVGuid 45556324-9a22-446e-8adb-65b29eb60943 -Verbose
   
  	.EXAMPLE
   	Get-MIIS_CSObject -Account HoofHearted -Domain Litware -ComputerName IceMelted -Verbose
#>
    param
    (     
		<#
		Specifies the Account name of the object to search for in an ADMA
		#>
        [parameter(ParameterSetName="QueryByAccountAndDomain")] 
        $Account,
		
		<#
		Specifies the Domain (netbios domain name) of the object to search for in an ADMA
		#>
        [parameter(ParameterSetName="QueryByAccountAndDomain")] 
        $Domain,

		<#
		Specifies the DistinguishedName of the object to search for
		#>
        [parameter(ParameterSetName="QueryByDNAndMA")] 
        $DN,
		
		<#
		Specifies ManagementAgent to search in
		#>
        [parameter(ParameterSetName="QueryByDNAndMA")] 
        $ManagementAgent,

		<#
		Specifies the Metaverse GUID to search for
		#>
        [parameter(ParameterSetName="QueryByMvGuid")]
        [Guid] 
        $MVGuid,
		
		<#
		Specifies the ComputerName where FIMSync is running 
		(defaults to localhost)
		#>		
        [String]
        $ComputerName = (hostname)
    )   
    switch ($PsCmdlet.ParameterSetName) 
    { 
        QueryByAccountAndDomain  
        { 
            $wmiFilter = "Account='{0}' and Domain='{1}'" -F $Account, $Domain    
        } 
        QueryByDNAndMA  
        { 
            $ma = Get-ManagementAgent $ManagementAgent
            if (-not $ma)
            {
                throw "Sorry, I was really hoping that MA would exist on this server."
            }
            $wmiFilter = "DN='{0}' and MaGuid='{1}'" -F $DN, $ma.Guid    
        } 
        QueryByMvGuid
        {            
            $wmiFilter = "MVGuid='{$MVGuid}'"    
        }
    }##Closing: switch ($PsCmdlet.ParameterSetName)
    
    Write-Verbose "Querying WMI using ComputerName: '$ComputerName'"
    Write-Verbose "Querying FIM Sync for a MIIS_CSObject using filter: $wmiFilter"
    Get-WmiObject -ComputerName $ComputerName -Class MIIS_CSObject -Namespace root/MicrosoftIdentityIntegrationServer -filter $wmiFilter  
}

function Format-XML($xmlFile, $indent=2)
{
	<#
   	.SYNOPSIS 
   	Formats an XML file
	#>
    $StringWriter = New-Object System.IO.StringWriter
    $XmlWriter = New-Object System.XMl.XmlTextWriter $StringWriter
    $xmlWriter.Formatting = "indented"
    $xmlWriter.Indentation = 4

    [XML]$xml = Get-Content $xmlFile
    $xml.WriteContentTo($XmlWriter)
    $XmlWriter.Flush()
    $StringWriter.Flush()
    $StringWriter.ToString()  | Out-File -Encoding "UTF8" -FilePath $xmlFile
}

function Format-FimSynchronizationConfigurationFiles
{
<#
   	.SYNOPSIS 
   	Formats the XML in the FIM Sync configuration files 

   	.DESCRIPTION
   	The FIM synchronization XMLs are not formatted when created by FIM.  This makes source control a little ugly when diffing the files.
	This function simply formats the XML files to make them easier to diff.

   	.OUTPUTS
   	None.  the function operates on the existing files.
   
   	.EXAMPLE
   	Format-FimSynchronizationConfigurationFiles c:\MyFimSyncConfigFolder
#>
   Param
   	(       
   		<#
		Specifies the folder containing the MA and MV XML files 
		(defaults to the current folder)
		#>		
        [parameter(Mandatory=$false)]
		[String]
		[ValidateScript({Test-Path $_})]
		$ServerConfigurationFolder = (Get-Location)
   	) 
	###Change to $ServerConfigurationFolder
	Write-Verbose "Changing to the directory: $ServerConfigurationFolder" 
	Set-Location $ServerConfigurationFolder
   
	###Process each of the MA XML files
	$maFiles=(get-item "MA-*.xml")
	foreach($maFile in $maFiles)
	{
	    Write-Verbose "Processing MA XML file: $maFile"

	    ###Clear the ReadOnly Flag
	    (get-item $maFile).Set_IsReadOnly($false)

	    ###Format the XMLFile
	    Format-XML $maFile

	    ###MatchtheMANametotheMAID
	    $maName=(select-xml $maFile -XPath "//ma-data/name").Node.InnerText
	    $maID=(select-xml $maFile -XPath "//ma-data/id").Node.InnerText

	    ###Only rename the file if it doesn't already contain the MA Name
	    if($maFile -inotcontains $maName)
	    {
	        Rename-Item $maFile -NewName "MA-$maName.XML"
	    }
	}
	Write-Verbose "Processing MV.XML file"

	###Clear the ReadOnly Flag
	(get-item "MV.xml").Set_IsReadOnly($false)
	###Format the MV XML file
	Format-XML "MV.xml"   
}

Function Assert-CSAttribute
{
<#
   .SYNOPSIS 
   Asserts that a CSObject contains the expected attribute value 

   .DESCRIPTION
   The Assert-CSAttribute function checks the CSObject for an attribute
   It then asserts the attribute value

   .OUTPUTS
   Console output with the assertion results
   
   .EXAMPLE
   $CSObject = Get-MIIS_CSObject -ManagementAgent AD -DN 'CN=HoofHearted,DC=IceMelted,DC=ca'
   C:\PS>Assert-CSAttribute -MIIS_CSObject $CSObject -CSAttributeName userPrincipalName -CSAttributeValue hoofhearted@icemelted.ca -Hologram UnappliedExportHologram
   
   .EXAMPLE
   Get-MIIS_CSObject -ManagementAgent AD -DN 'CN=HoofHearted,DC=IceMelted,DC=ca' | Assert-CSAttribute userPrincipalName hoofhearted@icemelted.ca
   
#>
    [CmdletBinding()]
    Param
       (        
        #The MIIS_CSObject as the WMI object from FIM     
        [parameter(Mandatory=$true, ValueFromPipeline=$true)]        
        $MIIS_CSObject,
        
        #The CS Attribute name to test
        [parameter(Mandatory=$true,Position=0)]
        [String]
        $CSAttributeName,

        #The CS Attribute value to test
    	[parameter(Mandatory=$true,Position=1)]
        $CSAttributeValue,
        
        #The location in the CSObject to look for the attribute
        #Must be one of: Hologram, EscrowedExportHologram, PendingImportHologram, UnappliedExportHologram, UnconfirmedExportHologram
        [parameter(Mandatory=$false,Position=2)]
        [ValidateSet(“Hologram”, “EscrowedExportHologram”, “PendingImportHologram”,"UnappliedExportHologram","UnconfirmedExportHologram")]
        [String[]]
        $Hologram = 'Hologram'
    ) 
	Process
	{
        [xml]$hologramXML= $MIIS_CSObject.($Hologram)

        $csAttribute = $hologramXML.entry.attr | where {$_.name -ieq $CSAttributeName}
        if (-not $csAttribute)
        {
            Write-Host "FAIL: $CSAttributeName not present." -ForegroundColor Red
            Continue
        }
        else
        {
        	Write-Verbose "$CSAttributeName found in the hologram"   
        		    
        	if ($CSAttributeValue -eq $csAttribute.value)
        	{
        		Write-Host ("PASS: $CSAttributeName has the expected value: '{0}'" -F $csAttribute.value) -ForegroundColor Green
        	}
        	else
        	{
        		Write-Host ("FAIL: $CSAttributeName expected value not equal to the actual value.`n`tExpected: '{0}'`n`tActual:   '{1}'" -F $CSAttributeValue, $csAttribute.value) -ForegroundColor Red
        	}	
        }	
	}##Closing: End
}##Closing: Function Assert-CSAttribute

Function Create-ImportfileFromCSEntry
{
<#
	.SYNOPSIS 
	Creates a Drop File from a Connector Space Object 

	.DESCRIPTION
	The Create-ImportfileFromCSEntry gets a CSObject and dumps its Synchronized Hologram to a drop file that can be used by a Run Profile that is configured to pick up drop files.

	.OUTPUTS
	None, but it generates a file containing the CSObject.
   
    .EXAMPLE
    Get-MIIS_CSObject -ManagementAgent AD -DN 'CN=HoofHearted,DC=IceMelted,DC=ca' | Create-ImportfileFromCSEntry -Verbose
   
    .EXAMPLE
    Get-MIIS_CSObject -ManagementAgent AD -DN 'CN=HoofHearted,DC=IceMelted,DC=ca' | Create-ImportfileFromCSEntry -Verbose -PassThru
   
    .EXAMPLE
    Get-MIIS_CSObject -ManagementAgent AD -DN 'CN=HoofHearted,DC=IceMelted,DC=ca' | Create-ImportfileFromCSEntry -Verbose -CopyToMADataFolder
   
    .EXAMPLE 
    Get-MIIS_CSObject -ManagementAgent AD -DN 'CN=HoofHearted,DC=IceMelted,DC=ca' | Create-ImportfileFromCSEntry -Hologram PendingImportHologram -Verbose
   
   
#>
    [CmdletBinding()]
    Param
       (        
        #The MIIS_CSObject as the WMI object from FIM     
        [parameter(Mandatory=$true, ValueFromPipeline=$true)]        
        $MIIS_CSObject,
        
        #Off by default. When supplied it will copy the output file to the MAData folder for the specified MA
        [Switch]
        $CopyToMADataFolder = $false,
        
        #The location in the CSObject to look for the attribute
        #Must be one of: Hologram, EscrowedExportHologram, PendingImportHologram, UnappliedExportHologram, UnconfirmedExportHologram
        [parameter(Mandatory=$false,Position=0)]
        [ValidateSet(“Hologram”, “EscrowedExportHologram”, “PendingImportHologram”,"UnappliedExportHologram","UnconfirmedExportHologram")]
        [String[]]
        $Hologram = 'Hologram',
        
        #Write the XML to output
        [Switch]
        $PassThru
    ) 
	Process
	{
        if (-not ($MIIS_CSObject.($Hologram)))
        {            
            $validHolograms = @()
            (“Hologram”, “EscrowedExportHologram”, “PendingImportHologram”,"UnappliedExportHologram","UnconfirmedExportHologram") | % { if ($MIIS_CSObject.($_)){$validHolograms += $_}}
            
            Write-Warning ("The CSObject does NOT have the specified hologram: $Hologram. Please Try Again. `nHINTING: The CSObject DOES have these holograms: {0}" -F ($validHolograms -join ', '))
            Continue ## Get outta this Process block without writing output to the pipeline
        }

        ### Construct a file name using the CS ID
        $outputFileName = "{0}-{1}.xml" -F $MIIS_CSObject.MaName,$MIIS_CSObject.MaGuid
        Write-Verbose "CSObject will output to this file name: $outputFileName"
        
        ### Change the CSEntry to look like an audit entry
        ### then output to the file
        Write-Verbose "Constructing the XML based on the CSObject's '$Hologram' Hologram..."
        $dropFileXml = @"
<?xml version="1.0" encoding="UTF-16" ?>
<mmsml xmlns="http://www.microsoft.com/mms/mmsml/v2" step-type="delta-import">
<directory-entries>
"@

        $dropFileXml += $MIIS_CSObject.($Hologram) -replace "<entry", "<delta operation='replace'" -replace "</entry>","</delta>"

        $dropFileXml += "</directory-entries></mmsml>"

        if ($PassThru)
        {
            Write-Output $dropFileXml
        }
        else
        {
            Write-Verbose "Saving the XML to file: '$outputFileName'"
            $dropFileXml | out-file -Encoding Unicode -FilePath $outputFileName
        }
        
        if ($CopyToMADataFolder)
        {
            $fimRegKey = Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\FIMSynchronizationService\Parameters 
            $maDataFileName = "{0}MaData\{1}\{2}" -F $fimRegKey.Path, $MIIS_CSObject.MaName, $outputFileName
            Write-Verbose "Saving the XML to file: '$maDataFileName'"           
            $dropFileXml | out-file -Encoding Unicode -FilePath $maDataFileName
        }

	}##Closing: Process
}##Closing: Function Create-ImportfileFromCSEntry

function Start-ManagementAgent
{
<#
.Synopsis
   Executes a Run Profile on a FIM Management Agent
.DESCRIPTION
   Uses WMI to call the Execute method on the WMI MIIS_ManagementAgent Class
.EXAMPLE
   Start-ManagementAgent corp 'TEST-DISO-DROPFILE (africa)'
.EXAMPLE
   Start-ManagementAgent myReallyBigMAOne 'FullImport' -AsJob
   Start-ManagementAgent myReallyBigMATwo 'FullImport' -AsJob
   Get-Job | Receive-Job
.EXAMPLE
   @(
    ('corp','TEST-DISO-DROPFILE (redmond)'),
    ('corp','TEST-DISO-DROPFILE (europed)'),
    ('corp','TEST-DISO-DROPFILE (africa)')
) | Start-ManagementAgent
.EXAMPLE
   @(
    ('corp','TEST-DISO-DROPFILE (redmond)'),
    ('corp','TEST-DISO-DROPFILE (europed)'),
    ('corp','TEST-DISO-DROPFILE (africa)')
) | Start-ManagementAgent -StopOnError
.EXAMPLE
   @(
    ('corp','TEST-DISO-DROPFILE (redmond)'),
    ('corp','TEST-DISO-DROPFILE (europed)'),
    ('corp','TEST-DISO-DROPFILE (africa)')
) | Start-ManagementAgent -AsJob
.EXAMPLE
try{
    Start-ManagementAgent CORP      'DISO (redmond)'     -StopOnError
    Start-ManagementAgent CORP      'DS (redmond)'       -StopOnError
    Start-ManagementAgent HOME  	'DISO (All Domains) '-StopOnError

    ### FIM Export, Import and Sync
    Start-ManagementAgent FIM   	'Export'             -StopOnError
    Start-ManagementAgent FIM   	'Delta Import'       -StopOnError
    Start-ManagementAgent FIM   	'Delta Sync'         -StopOnError
}
catch
{    
    ### Assign the Exception to a variable to play with
    $maRunException = $_

    ### Show the MA returnValue
    $maRunException.FullyQualifiedErrorId

    ### Show the details of the MA that failed
    $maRunException.TargetObject.MaGuid
    $maRunException.TargetObject.MaName
    $maRunException.TargetObject.RunNumber
    $maRunException.TargetObject.RunProfile
}
.EXAMPLE
try
{
    Start-ManagementAgent HoofHearted 'full import' -StopOnError
}
catch
{
    $_.TargetObject
}
.INPUTS
   Inputs to this cmdlet (if any)
.OUTPUTS
   String ReturnValue - returned by the Execute() method of the WMI MIIS_ManagementAgent Class
#>
    [CmdletBinding()]
    [OutputType([String])]
    Param
    (
        # Management Agent Name
        [Parameter(Position = 0,ParameterSetName='SingleRunProfile')]    
        [Alias("MA")] 
        [String]
        $ManagementAgentName,

        # RunProfile Name
        [Parameter(Position = 1,ParameterSetName='SingleRunProfile')]
        [ValidateNotNull()]
        [String]
        $RunProfile,

        # List of Management Agent Names and Run Profile Names
        [Parameter(ParameterSetName='MultipleRunProfiles',ValueFromPipeline = $true)]
        [Array]
        $RunProfileList,

        # StopOnError
        [Switch]
        $StopOnError,

        # Run the Management as a PowerShell Job
        [Switch]
        $AsJob

    )
    Process
    {
        switch ($PsCmdlet.ParameterSetName) 
        { 
            SingleRunProfile 
            {
                ### No action required here yet because the inputs are as we need them to be in this parameter set             
            }
            MultipleRunProfiles
            {
                ### Get the MA Name and Run Profile name from the array item
                $ManagementAgentName = $RunProfileList[0]
                $RunProfile = $RunProfileList[1]          
            }
        }##Closing: switch ($PsCmdlet.ParameterSetName)
		
        Write-Verbose "Using $ManagementAgentName as the MA name."
        Write-Verbose "Using $RunProfile as the RunProfile name."

        ### Get the WMI MA
        $ManagementAgent = Get-ManagementAgent $ManagementAgentName
        if (-not (Get-ManagementAgent $ManagementAgentName))
        {
            throw ("MA not found.{0}" -F $ManagementAgentName)
        }

        if ($AsJob)
        {
            Start-Job -Name "Start-ManagementAgent-$ManagementAgentName-$RunProfile" -ArgumentList $ManagementAgentName,$RunProfile  -ScriptBlock {
					### Use gwmi to get the MA - we already verified that the MA exists so this should be safe.  What could possibly go wrong?
                    $ManagementAgent = Get-WmiObject -Class MIIS_ManagementAgent -Namespace root/MicrosoftIdentityIntegrationServer -Filter ("Name='{0}'" -f $args[0]) 
                    $RunProfile = $args[1]
					
                    ### Execute the Run Profile on the MA
                    $ReturnValue = $ManagementAgent.Execute($RunProfile).ReturnValue 
        
                    ### Construct a nice little parting gift for our callers
                    $ReturnObject = New-Object PSObject -Property @{            
                        MaName = $ManagementAgent.Name            
                        RunProfile = $ManagementAgent.RunProfile().ReturnValue
                        ReturnValue = $ReturnValue
                        RunNumber = $ManagementAgent.RunNumber().ReturnValue
                        #MaGuid = $ManagementAgent.Guid
                    }    
        			
					### Return our output - this will be held in the job until the caller does Receive-Job
                    Write-Output $ReturnObject   
            }##Closing: Start-Job -ScriptBlow
        }##Closing if($AssJob)
        else
        {
            ### Execute the Run Profile on the MA
            $ReturnValue = $ManagementAgent.Execute($RunProfile).ReturnValue 
        
            ### Construct a nice little parting gift for our callers
            $ReturnObject = New-Object PSObject -Property @{            
                MaName = $ManagementAgent.Name            
                RunProfile = $ManagementAgent.RunProfile().ReturnValue
                ReturnValue = $ReturnValue
                RunNumber = $ManagementAgent.RunNumber().ReturnValue
                #MaGuid = $ManagementAgent.Guid
            }       

			### Return our output - this will get sent to the caller when the MA finishes
            Write-output $ReturnObject

		    ### Throw according to $StopOnError
		    if ($StopOnError -and $ReturnValue -ne 'success')
            {            
                throw New-Object Management.Automation.ErrorRecord @(
                    New-Object InvalidOperationException "Stopping because the MA status was not 'success': $ReturnValue"
                    $ReturnValue
                    [Management.Automation.ErrorCategory]::InvalidResult
                    $ReturnObject
                )
            }##Closing: if ($StopOnError...
        }##Closing: else - from if($AsJob)
    }##Closing: Process
}##Closing: fucntion Start-ManagementAgent

function Confirm-ManagementAgentCounts
{
<#
.Synopsis
   Validate the counters of a Management Agent's Connector Space
.DESCRIPTION
   Uses the WMI object of the MA to validate based on number and/or percentage
.EXAMPLE
   $managementAgentTolerances = @{
	    MaxNumImportAdd    	= 0
	    MaxNumExportAdd 	= 0
	    MaxPercentImportAdd = 0
	}
	'MyMAName' | Confirm-ManagementAgentCounts @managementAgentTolerances -ThrowWhenMaxExceeded -Verbose
.EXAMPLE
   	$managementAgentTolerances = @{
	    MaxNumImportAdd    	= 0
	    MaxNumExportAdd 	= 0
	    MaxPercentImportAdd = 0
	}
	Start-ManagementAgent MyMaName 'Export' | Confirm-ManagementAgentCounts @managementAgentTolerances -ThrowWhenMaxExceeded -Verbose
.EXAMPLE
	$managementAgentTolerances = @{
	    MaxNumImportDelete        = 1000
	    MaxNumExportDelete        = 1000
	    MaxPercentExportUpdateAdd = 10
	}

	Start-ManagementAgent MA1  	'Delta Import' -AsJob	
	Start-ManagementAgent MA2 	'Delta Import' -AsJob 	
	Start-ManagementAgent MA3 	'Delta Import' -AsJob	
	Get-Job | Wait-Job | Receive-Job | Confirm-ManagementAgentCounts @managementAgentTolerances -ThrowWhenMaxExceeded -Verbose

#>
    [CmdletBinding()]
    [OutputType([PSObject])]
    Param
    (
		[Parameter(Mandatory=$true, ValueFromPipelineByPropertyName = $true,ValueFromPipeline = $true)] 
        [Alias("MaName")]
        [String]             
        $ManagementAgentName,

        [Switch]
        $ThrowWhenMaxExceeded,

        [int]
        $MaxNumExportAdd,

        [int]
        $MaxNumExportUpdate,

        [int]
        $MaxNumExportDelete,

        [int]
        $MaxNumImportAdd,

        [int]
        $MaxNumImportUpdate,

        [int]
        $MaxNumImportDelete,

        [int]
        $MaxPercentExportAdd,

        [int]
        $MaxPercentExportUpdate,

        [int]
        $MaxPercentExportDelete,

        [int]
        $MaxPercentImportAdd,

        [int]
        $MaxPercentImportUpdate,

        [int]
        $MaxPercentImportDelete
    )
    Process
    {
	    ###
        ### Get the MA
        ###
        $ma = Get-ManagementAgent $ManagementAgentName
        if (-not $ma)
        {
           throw "Sorry, I was really hoping that MA would exist on this server."
        }
        Write-Verbose ("Using MA: {0}" -F $ma.Name)
	
        ###
        ### Get the current MA ConnectorSpace counters
        ###
		Write-Verbose "Getting the MA counters (this may take a while on a large MA..."
        $maCounts = $ma | Get-ManagementAgentCounts
        
        ###
        ### Use a PSObject to track the values that exceeded our expectations
        ###
        $violations = New-Object PSObject

        ###
        ### Loop thru the supplied tolerances, check each supplied tolerance
        ###
        $PSBoundParameters.GetEnumerator() | Where-Object {$_.Key -like 'Max*'} | ForEach-Object {
        
            ### For each supplied tolerance, derive the Name and Value
            ### Doing it this way means we don't have logic for EACH of the tolerances
            $ToleranceValue = $_.Value
            $ToleranceName =  $_.Key        
            Write-Verbose ("Todlerance Name '{0}' Max Value '{1}'" -F $ToleranceName,$ToleranceValue)

         	###
            ### Handle MaxNum* Tolerances
            ###
            if ($ToleranceName -like 'MaxNum*')
            {
                $WmiCounterName = $ToleranceName -replace 'Max'
                $ToleranceActualValue = [int]$maCounts.($WmiCounterName)
                Write-Verbose ("Todlerance Actual Value '{0}'" -F $ToleranceActualValue)

                if ($ToleranceActualValue -gt $ToleranceValue)        
                {
                    $violations | Add-Member -MemberType NoteProperty -Name ($ToleranceName -replace 'Max', 'Actual') -Value $maCounts.($WmiCounterName)
                }
            }
            ###
            ### Handle MaxPercent* Tolerances
            ###
            elseif ($ToleranceName -like 'MaxPercent*')
            {
                $WmiCounterName = $ToleranceName -replace 'MaxPercent', 'Num'
                $ToleranceActualValue = ([int]$maCounts.($WmiCounterName) / [int]$maCounts.NumCSObjects * 100)
                Write-Verbose ("Todlerance Actual Value '{0}'" -F $ToleranceActualValue)

                if ($ToleranceActualValue -gt $ToleranceValue)        
                {
                    $violations | Add-Member -MemberType NoteProperty -Name ($ToleranceName -replace 'Max', 'Actual') -Value $ToleranceActualValue
                }
            }
            ###
            ### Spaz out on unexpected Parameters
            ###
            else
            {
                throw ("Hey, how'd this get in here? We're not supposed to have a parameter named '{0}'. WTF?" -F $ToleranceName)
            }
        }##Closing $PSBoundParameters.GetEnumerator() | Where-Object...
        
        Write-Output $violations

        ###
        ### Throw if asked AND something worth throwing
        ###
        if ($ThrowWhenMaxExceeded -and ($violations | Get-Member -MemberType NoteProperty))
        {
            throw "Violators!"
        }
    }##Closing: Process
}##Closing: function Confirm-ManagementAgentCounts