Option Explicit
' Matikan ICS di semua koneksi (kembalikan ke kondisi awal)
Dim netshare, col, conn, props, sharing
Set netshare = CreateObject("HNetCfg.HNetShare.1")
Set col = netshare.EnumEveryConnection
For Each conn In col
    Set props = netshare.NetConnectionProps(conn)
    If props.Name = "Ethernet" Or props.Name = "Ethernet 2" Then
        Set sharing = netshare.INetSharingConfigurationForINetConnection(conn)
        sharing.DisableSharing
    End If
Next
WScript.Echo "ICS dimatikan"
