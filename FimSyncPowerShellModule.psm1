
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
        QueryByMvGuid
        {            
            $wmiFilter = "MVGuid='{$MVGuid}'"    
        }
    }##Closing: switch ($PsCmdlet.ParameterSetName)
    
    Write-Verbose "Querying WMI using ComputerName: '$ComputerName'"
    Write-Verbose "Querying FIM Sync for a MIIS_CSObject using filter: $wmiFilter"
    Get-WmiObject -ComputerName $ComputerName -Class MIIS_CSObject -Namespace root/MicrosoftIdentityIntegrationServer -filter $wmiFilter  
}
