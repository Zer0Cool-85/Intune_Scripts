[Parameter(Mandatory = $false)]
[string]$FooterNote

<Border Grid.Row="2" Padding="0,10,0,22">
    <StackPanel HorizontalAlignment="Center">

        <TextBlock x:Name="txtFooterNote"
                   Visibility="Collapsed"
                   TextWrapping="Wrap"
                   TextAlignment="Center"
                   FontSize="13"
                   FontWeight="Bold"
                   FontStyle="Italic"
                   Foreground="#6B7280"
                   Margin="20,0,20,12"/>

        <StackPanel Orientation="Horizontal"
                    HorizontalAlignment="Center"
                    VerticalAlignment="Center">

            <StackPanel x:Name="deferPanel"
                        Orientation="Horizontal"
                        VerticalAlignment="Center"
                        Margin="0,0,8,0">
                <ComboBox x:Name="cmbDeferHours"
                          Style="{StaticResource ModernComboBox}"/>

                <Button x:Name="btnDefer"
                        Content="Defer"
                        Width="115"
                        Height="46"
                        Style="{StaticResource SecondaryButton}"/>
            </StackPanel>

            <Button x:Name="btnSecondary"
                    Width="130"
                    Height="46"
                    Style="{StaticResource SecondaryButton}"
                    Margin="8,0,8,0"
                    IsCancel="True"/>

            <Button x:Name="btnPrimary"
                    Width="130"
                    Height="46"
                    Style="{StaticResource ModernButton}"
                    Margin="8,0,8,0"
                    IsDefault="True"/>
        </StackPanel>
    </StackPanel>
</Border>



$txtFooterNote = $window.FindName('txtFooterNote')



if ([string]::IsNullOrWhiteSpace($FooterNote)) {
    $txtFooterNote.Visibility = 'Collapsed'
}
else {
    $txtFooterNote.Text = $FooterNote
    $txtFooterNote.Visibility = 'Visible'
}
