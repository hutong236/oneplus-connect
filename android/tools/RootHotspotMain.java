import android.content.Context;
import android.os.Looper;
import java.lang.reflect.*;

/**
 * 以 root 身份运行的独立工具（经 su + app_process 调起，见 RootHotspot.kt）。
 * 用法：CLASSPATH=<jar> app_process / RootHotspotMain enable|disable
 * 退出码 0=成功 非0=失败。日志同时输出到 stdout。
 */
public class RootHotspotMain {
    static void log(String s) { System.out.println("[RootHotspot] " + s); System.out.flush(); }

    public static void main(String[] args) throws Exception {
        boolean enable = args.length > 0 && "enable".equals(args[0]);
        Looper.prepareMainLooper();
        Class<?> at = Class.forName("android.app.ActivityThread");
        Object thread = at.getMethod("systemMain").invoke(null);
        Context ctx = (Context) at.getMethod("getSystemContext").invoke(thread);

        Object tm = ctx.getSystemService("tethering");
        Class<?> tmClass = Class.forName("android.net.TetheringManager");
        if (tm == null) { log("无法获取 TetheringManager"); System.exit(2); }

        boolean invoked = false;
        if (enable) {
            Method start = null;
            for (Method m : tmClass.getMethods())
                if (m.getName().equals("startTethering") && m.getParameterTypes().length == 3) start = m;
            Class<?> cbIf = start.getParameterTypes()[start.getParameterTypes().length - 1];
            final boolean[] failed = {false};
            Object proxy = Proxy.newProxyInstance(cbIf.getClassLoader(), new Class[]{cbIf}, (p, m, a) -> {
                if (m.getName().contains("Failed")) { failed[0] = true; log("onTetheringFailed " + java.util.Arrays.toString(a)); }
                else log("callback " + m.getName());
                return null;
            });
            Class<?> firstType = start.getParameterTypes()[0];
            Object firstArg;
            if (firstType == int.class) {
                firstArg = 0;
            } else {
                Class<?> builderClass = Class.forName(firstType.getName() + "$Builder");
                Object b = builderClass.getConstructor(int.class).newInstance(0);
                try {
                    builderClass.getMethod("setExemptFromEntitlementCheck", boolean.class).invoke(b, true);
                } catch (Throwable ignored) { }
                firstArg = builderClass.getMethod("build").invoke(b);
            }
            Object[] call = new Object[start.getParameterTypes().length];
            call[0] = firstArg;
            for (int i = 1; i < call.length; i++) {
                if (java.util.concurrent.Executor.class.isAssignableFrom(start.getParameterTypes()[i]))
                    call[i] = (java.util.concurrent.Executor) (r) -> r.run();
                else call[i] = proxy;
            }
            start.invoke(tm, call);
            invoked = true;
            log("startTethering 已调用（root），轮询热点状态…");
        } else {
            Method stop = null;
            for (Method m : tmClass.getMethods())
                if (m.getName().equals("stopTethering") && m.getParameterTypes().length == 1) stop = m;
            stop.invoke(tm, 0);
            invoked = true;
            log("stopTethering 已调用（root）");
        }
        if (!invoked) { System.exit(2); }

        Object wifi = ctx.getSystemService(Context.WIFI_SERVICE);
        Method isEnabled = Class.forName("android.net.wifi.WifiManager").getMethod("isWifiApEnabled");
        for (int i = 0; i < 10; i++) {
            Thread.sleep(1500);
            boolean on = (Boolean) isEnabled.invoke(wifi);
            if (on == enable) { log("结果：热点 " + (on ? "已开启" : "已关闭")); System.exit(0); }
        }
        log("结果：轮询超时");
        System.exit(1);
    }
}
