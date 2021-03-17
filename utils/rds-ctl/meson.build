rds_ctl_sources = files(
    'rds-ctl.cpp',
)

rds_ctl_deps = [
    dep_libv4l2rds,
]

rds_ctl = executable('rds-ctl',
                     rds_ctl_sources,
                     install : true,
                     dependencies : rds_ctl_deps,
                     include_directories : v4l2_utils_incdir)
