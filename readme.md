# 使用方法
1. 第一步，先修改`download.config`中的源码链接，如 `src-git immortal https://github.com/kcro227/immortalwrt-mt798x-6.6.git;openwrt-24.10-6.6 src`
2. 第二步，执行`./scripts/firmforge.sh feeds`更新feeds包
3. 第三步，执行`./scripts/firmforge.sh config`进行初次配置
4. 第四步，执行`make -C src download -j16 V=s`下载所需要的软件包
5. 第五步，执行`./scripts/firmforge.sh build`编译，默认线程数为核心数，你也可以使用`BUILD_JOBS=1 ./scripts/firmforge.sh build`进行单线程编译

# 重复编译
当你只需要同步源码的更新的话，执行`./scripts/firmforge.sh full-build`即可完成更新和编译   
最后，你只需要执行`./scripts/firmforge.sh copy`即可将构建的文件复制到你指定的位置，路径在`copy.config`文件中修改
