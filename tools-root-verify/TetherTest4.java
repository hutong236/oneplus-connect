import android.content.Context;
import android.net.wifi.WifiConfiguration;
import android.net.wifi.WifiManager;
import android.os.Looper;
import java.lang.reflect.*;

public class TetherTest4 {
    static void log(String s) { System.out.println("[ApTest] " + s); System.out.flush(); }

    public static void main(String[] args) throws Exception {
        boolean enable = args.length == 0 || !"off".equals(args[0]);
        Looper.prepareMainLooper();
        Class<?> at = Class.forName("android.app.ActivityThread");
        Object thread = at.getMethod("systemMain").invoke(null);
        Context ctx = (Context) at.getMethod("getSystemContext").invoke(thread);
        WifiManager wm = (WifiManager) ctx.getSystemService(Context.WIFI_SERVICE);

        Method m = WifiManager.class.getMethod("setWifiApEnabled", WifiConfiguration.class, boolean.class);
        log("调用 setWifiApEnabled(null, " + enable + ")（shell 身份）…");
        Object r = m.invoke(wm, null, enable);
        log("返回 " + r);

        for (int i = 0; i < 6; i++) {
            Thread.sleep(1500);
            Object on = WifiManager.class.getMethod("isWifiApEnabled").invoke(wm);
            log("poll" + i + " isWifiApEnabled=" + on);
            if (Boolean.TRUE.equals(on) == enable) break;
        }
        log("done");
        System.exit(0);
    }
}
