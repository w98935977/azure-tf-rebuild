# 驗證與排障

以下是可重複執行的驗證步驟，並非已完成的實測聲明。本機使用 PowerShell。

## 1. 等待 OS 初始化

```powershell
$ips = terraform output -json public_ips | ConvertFrom-Json
$key = "$env:USERPROFILE/.ssh/azure-tf-lab"
ssh -i $key "azureuser@$($ips.vm01)" "sudo cloud-init status --wait"
ssh -i $key "azureuser@$($ips.vm02)" "sudo cloud-init status --wait"
```

預期 cloud-init 完成且沒有 error。若 SSH 失敗，先確認管理端目前的 public IPv4 與 `admin_cidr` 一致。手機熱點換 IP 後，修改 tfvars 並重新 plan / apply；檢查差異應以 SSH source 更新為主。

## 2. 檢查 VM02 服務

```powershell
ssh -i $key "azureuser@$($ips.vm02)" "systemctl is-active lab-http; sudo ss -lntp | grep ':8080'; curl -fsS http://127.0.0.1:8080"
```

逐項檢查：服務為 `active`、監聽 TCP/8080、回傳 `Hello from vm02 - built by Terraform`。這組指令的最後 exit code 不能代表每一項都成功。

## 3. 驗證允許路徑

```powershell
ssh -i $key "azureuser@$($ips.vm01)" "curl --connect-timeout 5 --max-time 10 -fsS http://10.20.2.4:8080"
```

預期同樣回傳 VM02 的測試頁。這能驗證 VM01 經私有 IP、subnet NSG 到 VM02 HTTP 服務的整條路徑。

## 4. 驗證外部來源被阻擋

在本機執行：

```powershell
curl.exe --connect-timeout 5 --max-time 10 "http://$($ips.vm02):8080"
```

預期無法連線，常見為 timeout。必須先確認步驟 2、3 成功，否則失敗也可能只是服務未啟動。單憑 timeout 不能獨立證明命中哪條 NSG 規則。

目前兩台 VM 的拓撲沒有第三台 VNet client；不要把外部拒絕測試寫成已驗證「其他 VNet 來源」也被阻擋。

## 5. 驗證無額外變更

```powershell
terraform plan -detailed-exitcode
$LASTEXITCODE
```

`0` 表示本次 plan 沒有差異，`1` 為錯誤，`2` 表示有變更。Image 使用 `latest`，日後重新 plan 或部署的版本可能與第一次不同，需檢查具體差異。

## 排障順序

| 現象 | 下一步 |
|---|---|
| 無法 SSH | 核對 Public IP、目前來源 `/32`、NSG 規則與 SSH key |
| cloud-init error | 查看 `/var/log/cloud-init-output.log` 與 `/var/log/cloud-init.log` |
| VM02 本機 HTTP 失敗 | 查看 `systemctl status lab-http`、`journalctl -u lab-http` 與 listener |
| VM02 本機成功，VM01 失敗 | 核對目的 IP、NSG 關聯、priority 與 VM01 私有 IP |
| 外部 8080 意外成功 | 檢查實際連到的 IP、effective NSG rules 與既有連線狀態 |
| VM size 不可用 | 檢查 East Asia 供應、subscription quota，再調整 `vm_size` |

## 結果紀錄模板

每次測試填實際日期、commit 與結果，分享前遮蔽 subscription ID 和個人 public IP。不要提交原始 tfstate、tfvars 或二進位 plan。

| 項目 | 實際結果 | 證據／備註 |
|---|---|---|
| 測試日期與 commit | 待填 | |
| terraform validate | 待填 | |
| network apply | 待填 | |
| compute apply | 待填 | |
| cloud-init | 待填 | |
| VM02 本機 HTTP | 待填 | |
| VM01 → VM02 | 待填 | |
| 外部 → VM02 拒絕 | 待填 | |
| 無差異 plan | 待填 | |
| destroy / RG 不存在 | 待填 | |
