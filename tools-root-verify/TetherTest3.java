import android.content.Context;
import android.os.IBinder;
import android.os.Looper;
import java.lang.reflect.*;

public class TetherTest3 {
    static void log(String s) { System.out.println("[TetherRaw] " + s); System.out.flush(); }

    public static void main(String[] args) throws Exception {
        String mode = args.length > 0 ? args[0] : "tether";
        String pkg = args.length > 1 ? args[1] : "com.android.settings";
        Looper.prepareMainLooper();
        Class<?> at = Class.forName("android.app.ActivityThread");
        Object thread = at.getMethod("systemMain").invoke(null);
        Context ctx = (Context) at.getMethod("getSystemContext").invoke(thread);

        IBinder b = (IBinder) Class.forName("android.os.ServiceManager")
                .getMethod("getService", String.class).invoke(null, "connectivity");
        Class<?> stubClass = Class.forName("android.net.ITetheringConnector$Stub");
        Object connector = stubClass.getMethod("asInterface", IBinder.class).invoke(null, b);
        Class<?> connectorIf = Class.forName("android.net.ITetheringConnector");

        Method target = null;
        for (Method m : connectorIf.getMethods()) {
            if (m.getName().equals(mode) && m.getParameterTypes().length >= 2
                    && m.getParameterTypes()[m.getParameterTypes().length - 1].getName().endsWith("IIntResultListener")) target = m;
        }
        if (target == null) { log("方法未找到: " + mode); return; }
        log("target: " + target.getName() + " " + java.util.Arrays.toString(target.getParameterTypes()));

        Class<?> listenerIf = target.getParameterTypes()[target.getParameterTypes().length - 1];
        Object listener = Proxy.newProxyInstance(listenerIf.getClassLoader(), new Class[]{listenerIf}, (p, m, a) -> {
            log(">> onResult: " + java.util.Arrays.toString(a));
            return null;
        });

        Object[] call;
        if (mode.equals("tether") || mode.equals("untether")) {
            call = new Object[]{ args.length > 2 ? args[2] : "wlan0", pkg, listener };
        } else if (mode.equals("stopTethering")) {
            call = new Object[]{ 0, pkg, listener };
        } else if (mode.equals("stopAllTethering")) {
            call = new Object[]{ pkg, listener };
        } else {
            log("未知模式 " + mode); return;
        }
        target.invoke(connector, call);
        log("已调用，等待回调");
        for (int i = 0; i < 4; i++) {
            Thread.sleep(1200);
            Object wifi = ctx.getSystemService(Context.WIFI_SERVICE);
            Object on = Class.forName("android.net.wifi.WifiManager").getMethod("isWifiApEnabled").invoke(wifi);
            log("poll" + i + " isWifiApEnabled=" + on);
        }
        log("done");
        System.exit(0);
    }
}
