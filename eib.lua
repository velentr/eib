#!/usr/bin/env lua

v = {
    major = 0,
    minor = 0,
}

-- load config.lua into the config table
config = {}
confun = loadfile("./config.lua")
setfenv(confun, config)
confun()

-- append an empty snapshot at the end for chroot/down changes to use; prevents
-- polluting the last snapshot with unrelated changes and allows chroot into the
-- final rootfs without having to find the last snapshot in use
config.snapshots[#config.snapshots+1] = {name = "root", modules = {}}

TARGET = config.path.target
QEMU = config.path.qemu

fs = {}
function fs.rmtree(dir)
    local rc = os.execute("rm -rf " .. dir)
    if rc ~= 0 then
        error("cannot remove " .. dir)
    end
end

function fs.mkdir(dir)
    local rc = os.execute("mkdir -p " .. dir)
    if rc ~= 0 then
        error("cannot create " .. dir)
    end
end

ckp = {}
function ckp.path(name)
    return "./snapshots/" .. name
end

function ckp.empty()
    return ckp.path(".empty")
end

function ckp.work()
    return ckp.path(".work")
end

function ckp.clear()
    local rc = os.execute("umount -R " .. TARGET)
    if rc ~= 0 then
        -- TODO we get an error here if the target is not mounted; figure out a
        -- way to ignore these errors
        -- error("cannot unmount " .. TARGET)
    end

    fs.rmtree(ckp.work())
end

function ckp.reset(name)
    ckp.clear()

    local clear = name == nil
    for i, snapshot in ipairs(config.snapshots) do
        if snapshot.name == name then
            clear = true
        end

        if clear then
            fs.rmtree(ckp.path(snapshot.name))
        end
    end
end

function ckp.lowerdirs(name)
    local result = ckp.empty()
    for i, snapshot in ipairs(config.snapshots) do
        if snapshot.name == name then
            return result
        end

        result = ckp.path(snapshot.name) .. ":" .. result
    end
end

function ckp.load(name)
    ckp.clear()
    fs.mkdir(ckp.empty())
    fs.mkdir(ckp.work())
    fs.mkdir(ckp.path(name))
    fs.mkdir(TARGET)

    local o = string.format(
        "-olowerdir=%s,upperdir=%s,workdir=%s",
        ckp.lowerdirs(name),
        ckp.path(name),
        ckp.path(".work")
    )
    local cmd = string.format("mount -t overlay overlay %s %s", o, TARGET)
    print(cmd)
    local rc = os.execute(cmd)
    if rc ~= 0 then
        error("cannot mount " .. name)
    end
end

function genenv(mod)
    local env = "env -i"
    for k, v in pairs(config[mod]) do
        env = env .. " " .. k .. "='" .. v .. "'"
    end
    return env
end

function shcontext(ctx)
    local reset = 0
    for i, commands in ipairs(ctx) do
        reset = i
        rc = os.execute(commands[1])
        if rc ~= 0 then
            break
        end
    end

    while reset > 0 do
        if ctx[reset][2] ~= nil then
            os.execute(ctx[reset][2])
        end
        reset = reset - 1
    end

    return rc
end

function chroot(command)
    ctx = {
        {"cp " .. QEMU .. " " .. TARGET .. "/usr/bin/",
         "rm " .. TARGET .. "/usr/bin/qemu-*"},
        {"mount -t proc /proc " .. TARGET .. "/proc",
         "umount " .. TARGET .. "/proc"},
        {"mount --rbind /sys " .. TARGET .. "/sys",
         "umount -l " .. TARGET .. "/sys"},
        {"mount --rbind /dev " .. TARGET .. "/dev",
         "umount -l " .. TARGET .. "/dev"},
        {"mkdir -p " .. TARGET .. "/proc/sys/fs/binfmt_misc", nil},
        {"mount --rbind /proc/sys/fs/binfmt_misc " .. TARGET .. "/proc/sys/fs/binfmt_misc",
         "umount " .. TARGET .. "/proc/sys/fs/binfmt_misc"},
        {"chroot " .. TARGET .. " " .. command, nil},
    }
    local rc = shcontext(ctx)

    return rc
end

function find_module(mod)
    -- TODO allow a list of paths and search through them
    return config.path.mod .. "/" .. mod .. ".sh"
end

function eib_run(stage, mod)
    local env = genenv(mod) .. " TARGET=" .. TARGET
    local modpath = find_module(mod)
    return env .. " " .. config.path.run .. " " .. stage .. " " .. modpath
end

function do_up(mod)
    rc = os.execute(eib_run("up", mod))
    if rc ~= 0 then
        error("failed bringing up " .. mod)
    end
end

function do_fix(mod)
    local env = genenv(mod)
    local modpath = "/opt/eib/" .. mod .. ".sh"
    -- busybox symlinks aren't installed yet (namely, /usr/bin/env doesn't
    -- exist), so we call the busybox binary directly
    rc = chroot("/bin/busybox " .. env .. " /opt/eib/eib-run.sh fix " .. modpath)
    if rc ~= 0 then
        error("failed fixing " .. mod)
    end
end

function do_down(mod)
    rc = os.execute(eib_run("down", mod))
    if rc ~= 0 then
        error("failed bringing up " .. mod)
    end
end

function do_setup_fix()
    local eib_path = TARGET .. "/opt/eib/"

    rc = os.execute("mkdir -p " .. eib_path)
    if rc ~= 0 then
        error("failed creating " .. eib_path)
    end

    for i, snapshot in ipairs(config.snapshots) do
        for j, mod in ipairs(snapshot.modules) do
            rc = os.execute("cp " .. find_module(mod) .. " " .. eib_path)
            if rc ~= 0 then
                error("failed copying " .. mod .. " to " .. eib_path)
            end
        end
    end

    rc = os.execute("cp " .. config.path.run .. " " .. eib_path)
    if rc ~= 0 then
        error("failed copying eib-run.sh to " .. eib_path)
    end
end

function do_teardown_fix()
    local eib_path = TARGET .. "/opt/eib/"

    rc = os.execute("rm -rf " .. eib_path)
    if rc ~= 0 then
        error("failed cleaning up " .. eib_path)
    end
end

function do_build(snapshot)
    if snapshot ~= nil then
        ckp.reset(snapshot)
    else
        ckp.reset()
    end

    local start = snapshot == nil
    for i, ss in ipairs(config.snapshots) do
        if ss.name == snapshot then
            start = true
        end

        if start then
            ckp.load(ss.name)
            for j, mod in ipairs(ss.modules) do
                do_up(mod)
            end
        end
    end

    do_setup_fix()

    for i, snapshot in ipairs(config.snapshots) do
        for j, mod in ipairs(snapshot.modules) do
            do_fix(mod)
        end
    end

    do_teardown_fix()

    for i = #config.snapshots, 1, -1 do
        snapshot = config.snapshots[i]
        for j, mod in ipairs(snapshot.modules) do
            do_down(mod)
        end
    end
end

function do_chroot(snapshot)
    -- if no snapshot is provided, load the final root snapshot
    if snapshot == nil then
        snapshot = "root"
    end

    -- load (but do not reset) the given snapshot
    ckp.load(snapshot)

    -- open a chroot shell
    chroot("/bin/sh")
end

commands = {
    build = function(i)
        if arg[i+1] ~= nil then
            error("unrecognized argument: " .. arg[i+1])
        end
        do_build(arg[i])
    end,
    chroot = function(i)
        if arg[i+1] ~= nil then
            error("unrecognized argument: " .. arg[i+1])
        end
        do_chroot(arg[i])
    end,
    version = function(i)
        if arg[i] ~= nil then
            error("unrecognized argument: " .. arg[i])
        end
        print("v" .. tostring(v.major) .. "." .. tostring(v.minor))
    end,
}

if arg[1] then
    if commands[arg[1]] == nil then
        error("unrecognized command: " .. arg[1])
    end
    commands[arg[1]](2)
else
    commands["build"](2)
end
