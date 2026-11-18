Option Explicit
' Aktifkan ICS: Ethernet (internet) -> Ethernet 2 (RNDIS)
Dim netshare, col, conn, props, sharing, pub, priv
Set netshare = CreateObject("HNetCfg.HNetShare.1")
Set col = netshare.EnumEveryConnection
For Each conn In col
    Set props = netshare.NetConnectionProps(conn)
    If props.Name = "Ethernet" Then Set pub = conn
    If props.Name = "Ethernet 2" Then Set priv = conn
Next
If pub Is Nothing Then WScript.Echo "PUBLIC NOT FOUND": WScript.Quit 1
If priv Is Nothing Then WScript.Echo "PRIVATE NOT FOUND": WScript.Quit 1
Set sharing = netshare.INetSharingConfigurationForINetConnection(pub)
sharing.EnableSharing 0
Set sharing = netshare.INetSharingConfigurationForINetConnection(priv)
sharing.EnableSharing 1
WScript.Echo "ICS aktif"
