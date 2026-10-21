BeforeAll {
    . "$PSScriptRoot\Test-OSDCloudInternetConnection.ps1"
}

Describe 'Test-OSDCloudInternetConnection' {
    It 'uses the Microsoft connectivity test endpoint by default' {
        Mock Invoke-WebRequest {}

        Test-OSDCloudInternetConnection | Should -BeTrue

        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Head' -and
            $Uri -eq 'http://www.msftconnecttest.com/connecttest.txt' -and
            $UseBasicParsing -and
            $Headers['Cache-Control'] -eq 'no-cache'
        }
    }
}
