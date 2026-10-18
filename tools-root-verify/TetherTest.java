import java.util.concurrent.Executor;
import java.lang.reflect.*;
import android.content.Context;
import android.os.Looper;

public class TetherTest {
    static void log(String s) { System.out.println("[TetherTest] " + s); System.out.flush(); }

    public static void main(String[] args) throws Exception {
        Looper.prepareMainLooper();
        Class<?> at = Class.forName("android.app.ActivityThread");
        Object thread = at.getMethod("systemMain").invoke(null);
        log("step1 systemMain ok");
        Context ctx = (Context) at.getMethod("getSystemContext").invoke(thread);
        log("step2 ctx=" + ctx);

        Class<?> tmClass = Class.forName("android.net.TetheringManager");
        Object tm = ctx.getSystemService("tethering");
        log("step3 tm via getSystemService=" + tm);
        if (tm == null) {
            try { tm = tmClass.getMethod("getInstance", Context.class).invoke(null, ctx); log("step3b getInstance=" + tm); } catch (Throwable t) { log("getInstance fail " + t); }
        }
        if (tm == null) { log("NO TM, exit"); return; }

        Method start = null;
        for (Method mm : tmClass.getMethods()) if (mm.getName().equals("startTethering")) start = mm;
        log("step4 signature=" + java.util.Arrays.toString(start.getParameterTypes()));

        Class<?> cbIf = start.getParameterTypes()[start.getParameterTypes().length - 1];
        Object proxy = Proxy.newProxyInstance(cbIf.getClassLoader(), new Class[]{cbIf}, (p, method, a) -> {
            log("callback " + method.getName() + " " + java.util.Arrays.toString(a));
            return null;
        });

        Class<?> firstType = start.getParameterTypes()[0];
        Object firstArg;
        if (firstType == int.class) { firstArg = 0; }
        else {
            Class<?> builder = Class.forName(firstType.getName() + "$Builder");
            Object b = builder.getConstructor(int.class).newInstance(0);
            try { builder.getMethod("setExemptFromEntitlementCheck", boolean.class).invoke(b, true); log("exempt=true"); }
            catch (Throwable t) { log("exempt fail " + t); }
            firstArg = builder.getMethod("build").invoke(b);
        }

        Object[] callArgs = new Object[start.getParameterTypes().length];
        callArgs[0] = firstArg;
        for (int i = 1; i < callArgs.length; i++) {
            if (Executor.class.isAssignableFrom(start.getParameterTypes()[i])) callArgs[i] = (Executor) (r) -> r.run();
            else callArgs[i] = proxy;
        }
        log("step5 invoking startTethering (shell uid)…");
        start.invoke(tm, callArgs);
        log("step6 invoke returned");

        for (int i = 0; i < 6; i++) {
            Thread.sleep(1500);
            Object wifi = ctx.getSystemService(Context.WIFI_SERVICE);
            Object on = Class.forName("android.net.wifi.WifiManager").getMethod("isWifiApEnabled").invoke(wifi);
            log("poll" + i + " isWifiApEnabled=" + on);
            if (Boolean.TRUE.equals(on)) break;
        }

        if (args.length > 0 && "stop".equals(args[0])) {
            for (Method mm : tmClass.getMethods())
                if (mm.getName().equals("stopTethering") && mm.getParameterTypes().length == 1) { mm.invoke(tm, 0); log("stopTethering invoked"); }
        }
        log("done");
        System.exit(0);
    }
}
