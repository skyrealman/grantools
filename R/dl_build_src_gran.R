#' Build packages w/ deps
#' 
#' Build GRAN packages w/ GRAN and CRAN deps
#' 
#' @param GRAN.dir local directory for GRAN built packages
#' @param lib local directory to install dependent packages
#' @import httr 
#' @import utils
#' @import devtools
#' @importFrom miniCRAN pkgDep
#' @export
dl_build_src <- function(GRAN.dir = 'GRAN', lib=.libPaths()[1]){
  repos=c(CRAN="https://cran.rstudio.com/", USGS='https://owi.usgs.gov/R')
  
  
  ################################################################################
  ## These options may need to be edited for your local system
  ## we try to infer the rest
  ################################################################################
  src_dir = file.path(GRAN.dir, 'src', 'contrib')
  ################################################################################
  ## /options
  ################################################################################
  
  ##Update all the local packages so we're always working with the latest
  update.packages(lib.loc = lib, repos=repos, ask = FALSE, 
                  type = "binary", contriburl = contrib.url(paste0('file:', GRAN.dir)))
  
  #current package source builds
  sourceBuildList <- paste0(src_dir,"/buildTags.tsv")
  packages = read_src_list(defaultPath = system.file("gran_source_list.tsv",package = "granbuild"), checkPath = sourceBuildList)
  if(nrow(packages) > 0){
    toDelete <-  sub(".*\\/","",packages$package)
    if(dir.exists(file.path(GRAN.dir, 'src'))){
      unlink(paste0(src_dir,"/",toDelete,"*")) #delete any existing version of toDelete packages
    }else{
      dir.create(src_dir, recursive = TRUE)
    }
    
    scratch = tempdir()
    all_deps = data.frame()
    
    for(i in 1:nrow(packages)){
      
      url = paste0('https://github.com/', packages$package[i], '/archive/', packages$tag[i], '.zip')
      
      GET(url, write_disk(file.path(scratch, 'package.zip'), overwrite=TRUE), timeout=600)
      
      unzip(file.path(scratch, 'package.zip'), exdir=file.path(scratch, packages$package[i]))
      
      pkgdirname = Sys.glob(paste0(scratch, '/', packages$package[i], '/', basename(packages$package[i]), '*'))
      
      all_deps = rbind(all_deps, as.data.frame(devtools::dev_package_deps(pkgdirname)))

      devtools::install_deps(pkgdirname, repos=repos, lib=lib, 
                             type = "binary", ask = FALSE)
      
      if(length(pkgdirname) > 1){
        stop('too many files in downloaded zip, ambiguous build info')
      }
      
      cmd = paste0('R CMD build ', pkgdirname, ' --no-build-vignettes --no-manual')
      system(cmd)
      write_PACKAGES(getwd(), type='source')
      gran_packages = data.frame(available.packages(paste0('file:', getwd()), type='source'))
      
      built_pkg = Sys.glob(paste0(gran_packages$Package,"_",gran_packages$Version,".tar.gz"))
      
      issuccess = file.rename(built_pkg, file.path(src_dir, basename(built_pkg)))
      
      if(!issuccess){
        stop('Cannot move package', packages$package[i], 'to local GRAN area')
      }
    }
    
    write_PACKAGES(src_dir, type='source')
    
    #now, install any missed packages using the local source directory 
    # this is necessary if more than one package is added to GRAN at a time
    # or GRAN is screwed up for some reason

    missed_pkgs = all_deps$package[!all_deps$package %in% installed.packages()[,1]]

    if(length(missed_pkgs) > 0){
      cat('Installing missed packages:', missed_pkgs)
      install.packages(unique(missed_pkgs), repos=paste0('file:', GRAN.dir), lib=lib, 
                       type = "binary", ask = FALSE)
    }
    
    writeBuildList(src_dir)
  } else {
    print("Source directory already up to date", quote = FALSE)
  }
  granPkg <- available.packages(contriburl = contrib.url( paste0('file:', GRAN.dir)))
  
  neededPkgs <- pkgDep(repos = c("https://cloud.r-project.org",paste0('file:', GRAN.dir)), 
                        pkg = rownames(granPkg), suggests = FALSE)
  needed.packages <- neededPkgs[!(neededPkgs %in% installed.packages(lib=lib)[,"Package"])]
  if(length(needed.packages) > 0){
    install.packages(needed.packages, 
                     repos = c(paste0('file:', GRAN.dir),
                               "https://cloud.r-project.org"),
                     lib=lib, type = "binary")
  }
}

#' generate a build list file in a directory
#' @param path character path to the folder to write buildList in
#' @import utils
#' @export

writeBuildList <- function(path){
  file.copy(system.file("gran_source_list.tsv",package = 'granbuild'),
            path, overwrite = TRUE)
  file.rename(paste0(path,"/gran_source_list.tsv"),paste0(path,"/buildTags.tsv"))
}

