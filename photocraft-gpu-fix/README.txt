PhotoCraft GPU Fix  (Windows 10/11, 64-bit)
===========================================

Ye kya hai
----------
PhotoCraft apna GPU compositor DirectX 12 se banata hai. Kuch PCs par Windows ka
purana shader compiler (FXC) us shader ko reject karta hai:

    error X3507: 'blend_channel': Not all control paths return a value
    GPU compositor: couldn't build the compositor's pipelines
    ; using the CPU compositor

Is ke baad app har launch par canvas CPU par banati hai: CPU load zyada rehta hai
aur GPU use nahi hota.

Ye package Microsoft ka DirectX Shader Compiler (DXC: dxcompiler.dll + dxil.dll)
PhotoCraft ke folder mein rakhta hai. Phir wahi shader DXC se compile hota hai
aur GPU compositor ban jata hai.

Kya chahiye
-----------
- Windows 10 ya 11, 64-bit
- PhotoCraft pehle se install ho (0.16 / 0.17 par test kiya gaya)
  https://github.com/storytold/photocraft/releases

Install kaise karein
--------------------
1. Poore zip ko extract karein (zip ke andar se direct na chalayein).
2. INSTALL.cmd par double-click karein.
3. UAC prompt par "Yes" dabayein.
4. Script PhotoCraft ko khud dhoondta hai, DLL copy karta hai, preferences set
   karta hai aur app ko 15 second chala kar check karta hai.

PhotoCraft kisi doosre folder mein ho to:
    INSTALL.cmd "D:\Apps\Photocraft"

Check
-----
PhotoCraft kholein: Preferences > Performance par GPU backend aur adapter ka naam
dikhna chahiye. Log bhi dekh sakte hain:
    %APPDATA%\Photocraft\logs\photocraft.log
Usme "using the CPU compositor" nahi aana chahiye.

Undo
----
UNINSTALL.cmd chalayein. Ye dono DLL hata deta hai aur preferences ka sab se naya
backup wapas laga deta hai (backup install ke waqt banta hai:
preferences.backup-<date>.json).

Admin ke bagair
---------------
Agar UAC na dena chahein to PhotoCraft-GPU.cmd se app start karein. Ye kuch
install nahi karta, sirf usi launch ke liye DXC use karwata hai.

Zaroori baat
------------
- Filters (Gaussian/Motion Blur, Sharpen, Twirl, Oil Paint, Noise waghera)
  upstream design ki wajah se CPU par hi chalte hain. GPU sirf canvas
  compositing, layer effects, blend modes aur Camera Raw preview ke liye hai.
  Heavy filter chalate waqt CPU phir bhi spike karega.
- PhotoCraft update karne par ye DLL hata sakta hai; us waqt INSTALL.cmd dobara
  chala lein.
- Ye upstream bug ka workaround hai, app ka modified build nahi. Report:
  https://github.com/storytold/photocraft/issues

Files
-----
INSTALL.cmd          install (double-click)
install.ps1          asli script (-InstallDir, -NoPrefs, -Verify, -Force)
UNINSTALL.cmd        undo
uninstall.ps1        undo script
PhotoCraft-GPU.cmd   admin ke bagair chalane ka launcher
bin\dxcompiler.dll   DirectX Shader Compiler v1.9.2609 (Microsoft)
bin\dxil.dll         DXIL signing library
bin\LICENSE-*.txt    inki licenses

Test kiya gaya: PhotoCraft 0.17.0 (b8c3f3aa8), Windows 11 26200,
Intel HD Graphics 530, driver 31.0.101.2111.
