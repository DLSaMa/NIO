//
//  PacketTunnelProvider.swift
//  PacketTunnel
//
//  Created by LiuJie on 2019/3/30.
//  Copyright © 2019 Lojii. All rights reserved.
//

import NetworkExtension
import TunnelServices
//import AxLogger
import Reachability
//import Bugly

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    // MARK: Properties
    
    open var connection: NWTCPConnection! //默认
    open var session:NWUDPSession!;
    var mitmServer: MitmService!
    var reachability = try! Reachability() //发生错误一定报错，？的话 发生错误返回nil
    
    /// 隧道完全建立时要调用的完成处理程序。
    var pendingStartCompletion: ((Error?) -> Void)!
    
    /// 隧道完全断开连接时要调用的完成处理程序。
    var pendingStopCompletion: (() -> Void)?
    
    // MARK: NEPacketTunnelProvider
    
    /// 开始建立隧道的过程。
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        pendingStartCompletion = completionHandler
        //        // 正常启动
        if StartInExtension {
            guard let server = MitmService.prepare() else {
                NSLog("Start Tunel Failed! MitmService create Failed !")
                self.pendingStartCompletion(nil)
                return
            }
            mitmServer = server
            mitmServer.run({(result) in
                switch result {
                case .success( _):
//                    let endpoint = NWHostEndpoint(hostname:"127.0.0.1", port:"8034")//是表示网络端点的抽象基类，例如远程服务器上的端口。 所有实例都应使用NWHostEndpoint或NWBonjourServiceEndpoint之一的子类创建。
//                    self.connection = self.createTCPConnection(to: endpoint, enableTLS:false, tlsParameters:nil, delegate:nil)
//
                    let udpPoint = NWHostEndpoint(hostname:"127.0.0.1", port:"9527")
                    //  NWEndpoint 对象，该对象指定 UDP 会话将发送到的 UDP 数据报的远程终结点
                    //  NWHostendpoint 对象，该对象指定要用作 UDP 会话的源终结点的本地 IP 地址终结点
                    self.session = self.createUDPSession(to: udpPoint, from: nil)
                    
                    self.startVPNWithOptions(options: nil) { (error) in
                        if error == nil {
                            NSLog("***************** Start Tunel Success !")
                            //                            MitmService.sendLog(msg: "***************** Start Tunel Success !")
                            self.readPakcets()
                            self.pendingStartCompletion(nil)
                            
                        }else{
                            NSLog("***************** Start Tunel Failed!",error!.localizedDescription)
                            self.pendingStartCompletion(error)
                        }
                    }
                case .failure(let error):
                    NSLog("***************** MitmService Run Failed! \(error.localizedDescription)")
                    self.pendingStartCompletion(error)
                    break
                }
            })
        }else{
            // 单独启动
//            let endpoint = NWHostEndpoint(hostname:"127.0.0.1", port:"8034")
//            self.connection = self.createTCPConnection(to: endpoint, enableTLS:false, tlsParameters:nil, delegate:nil)
//            
            
            let udpPoint = NWHostEndpoint(hostname:"127.0.0.1", port:"9527")
            self.session = self.createUDPSession(to: udpPoint, from: nil)
            
            self.startVPNWithOptions(options: nil) { (error) in
                if error == nil {
                    NSLog("Start Tunel Success !")
                    self.readPakcets()
                    self.pendingStartCompletion(nil)
                }else{
                    NSLog("Start Tunel Failed!",error!.localizedDescription)
                    self.pendingStartCompletion(error)
                }
            }
        }
        
        // 网络监控        
        NotificationCenter.default.addObserver(self, selector: #selector(reachabilityChanged(note:)), name: .reachabilityChanged, object: reachability)
        do{
            try reachability.startNotifier()
        }catch{
            print("could not start reachability notifier")
        }
        
    }
    
    func startVPNWithOptions(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        networkSettings.mtu = 1500
        
        let proxySettings = NEProxySettings()
        proxySettings.httpServer = NEProxyServer(address: "127.0.0.1", port: 8034)
        proxySettings.httpEnabled = true
        
        proxySettings.httpsServer = NEProxyServer(address: "127.0.0.1", port: 8034)
        proxySettings.httpsEnabled = true
        proxySettings.matchDomains = [""]
        //        proxySettings.matchDomains = ["www.baidu.com"]//["www.baidu.com","www.jianshu.com","127.0.0.1"]
        networkSettings.proxySettings = proxySettings
        
        let ipv4Settings = NEIPv4Settings(addresses: ["192.169.89.1"], subnetMasks: ["255.255.255.0"])
        networkSettings.ipv4Settings = ipv4Settings
        setTunnelNetworkSettings(networkSettings) { (error) in
            completionHandler(error)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        pendingStartCompletion = nil
        pendingStopCompletion = completionHandler
        // TODO:stop server
        if StartInExtension {
            mitmServer.close()
        }
    }
    
    func readPakcets() -> Void {
        packetFlow.readPackets { (packets, protocols) in
            
            let mutaData  = NSMutableData()
            for packet in packets {
                NSLog("Read Packet:",String(data: packet, encoding: .utf8) ?? "unknow")
                self.connection.write(packet, completionHandler: { (error) in
                    if let e = error {
                        //                        AxLogger.log("write packet error :\(e.localizedDescription)", level: .Error)
                        NSLog("write packet error :\(e.localizedDescription)")
                    }
                })
                mutaData.append(packet)
            }
            
            
            let messageString = NSString(data: mutaData as Data, encoding: String.Encoding.utf8.rawValue)
            NSLog("读取的数据:", messageString ?? "unknow")
            
            self.readPakcets()
        }
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        
    }
    
    @objc func reachabilityChanged(note: Notification) {
        //        mitmServer = mitmServer.restart()
        //        mitmServer.run { (r) in
        //            switch r {
        //            case .success(_):
        //                NSLog("重启运行成功")
        //            case .failure(_):
        //                NSLog("重启运行失败")
        //            }
        //        }
        //        let reachability = note.object as! Reachability
        //        switch reachability.connection {
        //        case .wifi:
        //            mitmServer.wifiNetWorkChanged(isOpen: true)
        //        case .cellular,.none:
        //            mitmServer.wifiNetWorkChanged(isOpen: false)
        //        }
    }
}
