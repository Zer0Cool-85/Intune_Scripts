@{
    # Window layout and behavior.
    Application = @{
        WindowTitle      = 'Device Support Information'
        Subtitle         = 'Copy the details your support team needs.'
        Width            = 760
        Height           = 720
        MinWidth         = 680
        MinHeight        = 600
        Columns          = 2
        Resizable        = $true
        ShowPrivacyNotice = $true
    }

    # LogoPath and IconPath can be absolute, but project-relative paths are
    # recommended so they can be included automatically in portable builds.
    Branding = @{
        LogoPath                  = ''
        FallbackMark              = 'i'
        AccentColor               = '#5BA63C'
        AccentHoverColor          = '#70BF50'
        WindowColor               = '#111827'
        HeaderColor               = '#151E2D'
        CardColor                 = '#1B2535'
        CardBorderColor           = '#2B3749'
        PrimaryTextColor          = '#F8FAFC'
        SecondaryTextColor        = '#9AA9BC'
        SecondaryButtonColor      = '#273347'
        SecondaryButtonHoverColor = '#34435A'
        InfoPanelColor            = '#183522'
        InfoPanelBorderColor      = '#2D5B38'
        InfoPanelTextColor        = '#D9F1D2'
        SuccessTextColor          = '#90EE90'
        ErrorTextColor            = '#F08080'
    }

    # Leave Url empty to hide the service desk button.
    ServiceDesk = @{
        Enabled    = $true
        Url        = ''
        ButtonText = 'Open service desk'
    }

    # All user-facing text can be changed here without editing the modules.
    Text = @{
        PrivacyNotice                  = 'Nothing is submitted automatically. Information is only copied when you choose Copy.'
        DefaultStatus                  = 'Choose one value or copy the full ticket summary.'
        CopySummaryButton              = 'Copy ticket summary'
        RefreshButton                  = 'Refresh'
        Unavailable                    = 'Unavailable'
        DateFormat                     = 'MMM d, yyyy h:mm tt'
        RefreshingMessage              = 'Refreshing device details...'
        RefreshCompleteMessage         = 'Device details are up to date.'
        RefreshErrorMessage            = 'Some device details could not be refreshed.'
        RefreshBeforeCopyMessage       = 'Refresh the device details before copying.'
        SummaryCopiedMessage           = 'Ticket summary copied — paste it into your support request.'
        ClipboardErrorMessage          = 'The clipboard is busy. Please try again.'
        NoValueMessage                 = 'There is no value available to copy.'
        ServiceDeskOpeningMessage      = 'Opening the service desk in your default browser.'
        ServiceDeskErrorMessage        = 'The service desk could not be opened. Please try again.'
        ServiceDeskNotConfiguredMessage = 'A service desk URL has not been configured.'
    }

    Summary = @{
        Heading            = 'DEVICE SUPPORT INFORMATION'
        IncludeCollectedAt = $true
        CollectedLabel     = 'Collected'
    }

    # Reorder these entries to change the UI order. Change Visible to $false to
    # hide a card. IncludeInSummary controls the full copied ticket text.
    Fields = @(
        @{
            Key              = 'DeviceName'
            Label            = 'Device name'
            Section          = 'Device'
            Visible          = $true
            IncludeInSummary = $true
        }
        @{
            Key              = 'SignedInUser'
            Label            = 'Signed-in user'
            Section          = 'Device'
            Visible          = $true
            IncludeInSummary = $true
        }
        @{
            Key              = 'Hardware'
            Label            = 'Manufacturer / model'
            Section          = 'Device'
            Visible          = $true
            IncludeInSummary = $true
        }
        @{
            Key              = 'SerialNumber'
            Label            = 'Serial / service tag'
            Section          = 'Device'
            Visible          = $true
            IncludeInSummary = $true
        }
        @{
            Key              = 'InstalledMemory'
            Label            = 'Installed memory'
            Section          = 'Device'
            Visible          = $true
            IncludeInSummary = $true
        }
        @{
            Key              = 'JoinStatus'
            Label            = 'Device join'
            Section          = 'Device'
            Visible          = $true
            IncludeInSummary = $true
        }

        @{
            Key              = 'WindowsEdition'
            Label            = 'Edition'
            SummaryLabel     = 'Edition'
            Section          = 'Windows'
            Visible          = $true
            IncludeInSummary = $true
        }
        @{
            Key              = 'WindowsVersion'
            Label            = 'Version'
            SummaryLabel     = 'Version'
            Section          = 'Windows'
            Visible          = $true
            IncludeInSummary = $true
        }
        @{
            Key              = 'OSBuild'
            Label            = 'OS build'
            Section          = 'Windows'
            Visible          = $true
            IncludeInSummary = $true
        }
        @{
            Key              = 'Architecture'
            Label            = 'Architecture'
            Section          = 'Windows'
            Visible          = $true
            IncludeInSummary = $true
        }
        @{
            Key              = 'LastRestart'
            Label            = 'Last restart'
            Section          = 'Windows'
            Visible          = $true
            IncludeInSummary = $true
        }
        @{
            Key              = 'Uptime'
            Label            = 'Uptime'
            Section          = 'Windows'
            Visible          = $true
            IncludeInSummary = $true
        }

        @{
            Key              = 'SystemDrive'
            Label            = 'System drive (C:)'
            SummaryLabel     = 'System drive'
            Section          = 'Storage & network'
            Visible          = $true
            IncludeInSummary = $true
        }
        @{
            Key              = 'ActiveConnection'
            Label            = 'Active connection'
            Section          = 'Storage & network'
            Visible          = $true
            IncludeInSummary = $true
        }
        @{
            Key              = 'IPv4Address'
            Label            = 'IPv4 address'
            Section          = 'Storage & network'
            Visible          = $true
            IncludeInSummary = $true
        }
        @{
            Key              = 'CollectedAt'
            Label            = 'Details refreshed'
            Section          = 'Storage & network'
            Visible          = $true
            IncludeInSummary = $false
        }
    )

    # Windows Explorer metadata used by build/Build-Exe.ps1.
    Build = @{
        OutputFileName = 'SystemSupportInfo.exe'
        ProductName    = 'System Support Information'
        Description    = 'Displays copy-friendly Windows device information for support requests.'
        Company        = 'Your Organization'
        Copyright      = 'Copyright (c) 2026 Your Organization'
        Version        = '1.0.2.0'
        IconPath       = ''
    }
}
