import android.content.Context;
import android.os.IBinder;
import android.os.Looper;
import android.os.Parcel;
import android.os.Parcelable;
import java.lang.reflect.*;

public class TetherTest2 {
    static void log(String s) { System.out.println("[SpoofTest] " + s); System.out.flush(); }

    public static void main(String[] args) throws Exception {
        Looper.prepareMainLooper();
        Class<?> at = Class.forName("android.app.ActivityThread");
        Object thread = at.getMethod("systemMain").invoke(null);
        Context ctx = (Context) at.getMethod("getSystemContext").invoke(thread);
        log("ctx ok");

        IBinder b = (IBinder) Class.forName("android.os.ServiceManager")
                .getMethod("getService", String.class).invoke(null, "connectivity");
        log("binder connectivity = " + b);

        Class<?> stubClass = Class.forName("android.net.ITetheringConnector$Stub");
        Object connector = stubClass.getMethod("asInterface", IBinder.class).invoke(null, b);
        Class<?> connectorIf = Class.forName("android.net.ITetheringConnector");
        log("connector = " + connector);

        // 枚举 connector 方法
        for (Method m : connectorIf.getMethods()) log("iface method: " + m.getName() + " " + java.util.Arrays.toString(m.getParameterTypes()));

        // 找 startTethering(TetheringRequestParcel, String, IIntResultListener)
        Method start = null;
        for (Method m : connectorIf.getMethods()) {
            if (m.getName().equals("startTethering") && m.getParameterTypes().length == 3) start = m;
        }
        if (start == null) { log("startTethering 3参方法未找到"); return; }
        log("startTethering: " + java.util.Arrays.toString(start.getParameterTypes()));

        Class<?> parcelClass = start.getParameterTypes()[0];
        Class<?> listenerIf = start.getParameterTypes()[2];
        Object listener = Proxy.newProxyInstance(listenerIf.getClassLoader(), new Class[]{listenerIf}, (p, m, a) -> {
            log(">> onResult: " + java.util.Arrays.toString(a));
            return null;
        });

        // 构造 TetheringRequestParcel：优先 Builder，否则从 TetheringRequest 复制 parcel
        Object parcelReq = null;
        try {
            Class<?> pb = Class.forName(parcelClass.getName() + "$Builder");
            Object bb = pb.getDeclaredConstructor().newInstance();
            pb.getMethod("setTetheringType", int.class).invoke(bb, 0);
            try { pb.getMethod("setExemptFromEntitlementCheck", boolean.class).invoke(bb, true); } catch (Throwable ignored) { }
            parcelReq = pb.getMethod("build").invoke(bb);
            log("TetheringRequestParcel via Builder ok");
        } catch (Throwable t) {
            log("Builder 方式失败: " + t + "，改用 parcel 复制");
            Class<?> reqB = Class.forName("android.net.TetheringManager$TetheringRequest$Builder");
            Object bld = reqB.getConstructor(int.class).newInstance(0);
            try { reqB.getMethod("setExemptFromEntitlementCheck", boolean.class).invoke(bld, true); } catch (Throwable ignored) { }
            Object request = reqB.getMethod("build").invoke(bld);
            Parcel p = Parcel.obtain();
            ((Parcelable) request).writeToParcel(p, 0);
            p.setDataPosition(0);
            Object creator = parcelClass.getField("CREATOR").get(null);
            parcelReq = creator.getClass().getMethod("createFromParcel", Parcel.class).invoke(creator, p);
            log("parcel 复制 ok: " + parcelReq);
        }

        String spoofPkg = args.length > 0 ? args[0] : "com.android.settings";
        log("以 callerPkg=" + spoofPkg + " 调用 startTethering…");
        start.invoke(connector, parcelReq, spoofPkg, listener);
        log("调用已返回，等待回调…");

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
