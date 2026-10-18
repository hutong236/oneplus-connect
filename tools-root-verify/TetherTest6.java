import android.content.Context;
import android.os.IBinder;
import android.os.Looper;
import java.lang.reflect.*;

public class TetherTest6 {
    static void log(String s) { System.out.println("[Spoof6] " + s); System.out.flush(); }

    public static void main(String[] args) throws Exception {
        String pkg = args.length > 0 ? args[0] : "com.android.settings";
        Looper.prepareMainLooper();
        Class<?> at = Class.forName("android.app.ActivityThread");
        Object thread = at.getMethod("systemMain").invoke(null);
        Context ctx = (Context) at.getMethod("getSystemContext").invoke(thread);

        IBinder b = (IBinder) Class.forName("android.os.ServiceManager")
                .getMethod("getService", String.class).invoke(null, "connectivity");
        Object connector = Class.forName("android.net.ITetheringConnector$Stub")
                .getMethod("asInterface", IBinder.class).invoke(null, b);
        Class<?> connectorIf = Class.forName("android.net.ITetheringConnector");

        Method start = null;
        for (Method m : connectorIf.getMethods())
            if (m.getName().equals("startTethering") && m.getParameterTypes().length == 3) start = m;

        Class<?> parcelClass = start.getParameterTypes()[0];
        log("parcel 类: " + parcelClass.getName());
        for (Constructor<?> c : parcelClass.getConstructors())
            log("ctor: " + c.getParameterCount() + " 参数");
        Object req = parcelClass.getConstructors()[0].newInstance();
        for (Field f : parcelClass.getFields()) {
            String n = f.getName();
            log("field: " + n + " : " + f.getType());
            if (n.contains("tetheringType") || n.equals("tetheringType") || n.contains("TetheringType")) {
                if (f.getType() == int.class) f.set(req, 0);
            }
            if (n.toLowerCase().contains("exempt")) {
                if (f.getType() == boolean.class) f.set(req, true);
            }
            if (n.contains("interfaces") && f.getType() == String[].class) f.set(req, new String[0]);
        }

        Class<?> listenerIf = start.getParameterTypes()[2];
        Object listener = Proxy.newProxyInstance(listenerIf.getClassLoader(), new Class[]{listenerIf}, (p, m, a) -> {
            switch (m.getName()) {
                case "asBinder": return new android.os.Binder();
                case "toString": return "spoofListener";
                case "hashCode": return System.identityHashCode(p);
                case "equals": return p == (a == null ? null : a[0]);
                default:
                    log(">> " + m.getName() + ": " + java.util.Arrays.toString(a));
                    return null;
            }
        });

        log("startTethering(parcel, callerPkg=" + pkg + ", listener) …");
        start.invoke(connector, req, pkg, listener);
        log("已调用");

        for (int i = 0; i < 5; i++) {
            Thread.sleep(1500);
            Object wifi = ctx.getSystemService(Context.WIFI_SERVICE);
            Object on = Class.forName("android.net.wifi.WifiManager").getMethod("isWifiApEnabled").invoke(wifi);
            log("poll" + i + " isWifiApEnabled=" + on);
            if (Boolean.TRUE.equals(on)) break;
        }
        log("done");
        System.exit(0);
    }
}
