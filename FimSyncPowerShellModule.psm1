
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