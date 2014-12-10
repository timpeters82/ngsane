#!/bin/bash -e

# Script running fit-hi-c to call significant chromatin interactions form HiC 
# experiments. Expects bam files as input.
# author: Fabian Buske
# date: Oct 2014

# messages to look out for -- relevant for the QC.sh script:
# QCVARIABLES,Resource temporarily unavailable

echo ">>>>> Chromatin organization with fit-hi-c "
echo ">>>>> startdate "`date`
echo ">>>>> hostname "`hostname`
echo ">>>>> job_name "$JOB_NAME
echo ">>>>> job_id "$JOB_ID
echo ">>>>> $(basename $0) $*"

function usage {
echo -e "usage: $(basename $0) -k NGSANE -f FASTQ -o OUTDIR [OPTIONS]"
exit
}

if [ ! $# -gt 3 ]; then usage ; fi

#INPUTS
while [ "$1" != "" ]; do
    case $1 in
        -k | --toolkit )        shift; CONFIG=$1 ;; # location of the NGSANE repository
        -f | --file )           shift; FILES=$1 ;; # input files
        -o | --outdir )         shift; OUTDIR=$1 ;; # output dir
        --recover-from )        shift; NGSANE_RECOVERFROM=$1 ;; # attempt to recover from log file
        -h | --help )           usage ;;
        * )                     echo "don't understand "$1
    esac
    shift
done

#PROGRAMS
. $CONFIG
. ${NGSANE_BASE}/conf/header.sh
. $CONFIG

################################################################################
NGSANE_CHECKPOINT_INIT "programs"

# save way to load modules that itself loads other modules
hash module 2>/dev/null && for MODULE in $MODULE_FITHIC; do module load $MODULE; done && module list 

export PATH=$PATH_FITHIC:$PATH
echo "PATH=$PATH"
#this is to get the full path (modules should work but for path we need the full path and this is the\
# best common denominator)

echo -e "--NGSANE      --\n" $(trigger.sh -v 2>&1)
echo -e "--Python      --\n" $(python --version)
[ -z "$(which python)" ] && echo "[ERROR] no python detected" && exit 1
hash module 2>/dev/null && echo -e "--Python libs --\n "$(yolk -l)
echo -e "--HiCorrector --\n "$(ic_mep 2>&1 | tee | grep Version)
[ -z "$(which ic_mep)" ] && echo "[ERROR] no HiCorrection detected" && exit 1
echo -e "--fit-hi-c    --\n "$(python $(which fit-hi-c.py) --version | head -n 1)
[ -z "$(which fit-hi-c.py)" ] && echo "[ERROR] no fit-hi-c detected" && exit 1
echo -e "--TADbit      --\n "$(yolk -l | fgrep -w TADbit | fgrep -v -w "non-active")
if [[ "$(yolk -l | fgrep -w TADbit | fgrep -v -w "non-active" | wc -l | awk '{print $1}')" == 0 ]]; then echo "[WARN] no TADbit detected"; TADBIT=""; else TADBIT="--create2DMatrixPerChr"; fi

NGSANE_CHECKPOINT_CHECK
################################################################################
NGSANE_CHECKPOINT_INIT "parameters"

DATASETS="$(echo $FILES | tr ',' ' ')"
echo "[NOTE] Files: $DATASETS"

if [ -z "$FITHIC_POOLED_SAMPLE_NAME" ]; then 
    echo "[ERROR] variable not set: FITHIC_POOLED_SAMPLE_NAME"
    exit 1
else
    SAMPLE=$FITHIC_POOLED_SAMPLE_NAME
    echo "Sample name: $SAMPLE"
fi

# delete old bam files unless attempting to recover
if [ -z "$NGSANE_RECOVERFROM" ]; then
    [ -d $OUTDIR/$SAMPLE ] && rm -r $OUTDIR/$SAMPLE
    [ -f $OUTDIR/$SAMPLE.log ] && rm $OUTDIR/$SAMPLE.log
fi

GENOME_CHROMSIZES=${FASTA%.*}.chrom.sizes
if [ ! -f $GENOME_CHROMSIZES ]; then
    echo "[WARN] GENOME_CHROMSIZES not found. No bigbeds will be generated"
else
    echo "[NOTE] Chromosome size: $GENOME_CHROMSIZES"
fi

if [ -z "$HICORRECTOR_MAXITER" ];then
    echo "[NOTE] HICORRECTOR_MAXITER set to 100 by default"
    HICORRECTOR_MAXITER=100
fi

if [ -z "$MAPPABILITY" ]; then
    echo "[ERROR] Mappability not specified"
    exit 1
fi

if [ -z "$HIC_RESOLUTION" ]; then
    echo "[ERROR] HiC resolution not specified"
    exit 1
fi

if [[ -z "$FITHIC_QVALUETHRESHOLD" ]]; then
    FITHIC_QVALUETHRESHOLD=0.01
fi
echo "[NOTE] Q-value threshold: $FITHIC_QVALUETHRESHOLD"

if [[ -z "$FITHIC_MAPPABILITYTHRESHOLD" ]];then
    echo "[ERROR] FITHIC_MAPPABILITYTHRESHOLD not set"
    exit 1
fi

if [[ -n "$FITHIC_CHROMOSOMES" ]]; then
    FITHIC_CHROMOSOMES="--chrompattern '$FITHIC_CHROMOSOMES'"
fi

THISTMP=$TMP"/"$(whoami)"/"$(echo $OUTDIR/$SAMPLE | md5sum | cut -d' ' -f1)
[ -d $THISTMP ] && rm -r $THISTMP
mkdir -p $THISTMP

NGSANE_CHECKPOINT_CHECK
################################################################################
NGSANE_CHECKPOINT_INIT "recall files from tape"

if [ -n "$DMGET" ]; then
	dmget -a $f
	dmget -a $OUTDIR/*
fi

NGSANE_CHECKPOINT_CHECK

################################################################################
NGSANE_CHECKPOINT_INIT "count Interactions"

if [[ $(NGSANE_CHECKPOINT_TASK) == "start" ]]; then

    # ensure name sorted bam required
    SORTEDDATASET=""
    for DATA in $DATASETS; do 
        D=${DATA##*/}
        D=${D/%$ASD.bam/}
        samtools sort -O bam -@ $CPU_FITHIC -o $THISTMP/$D.bam -T $THISTMP/$D $DATA
        SORTEDDATASET="$SORTEDDATASET $THISTMP/$D.bam"
    done

    mkdir -p $OUTDIR/$SAMPLE
    RUN_COMMAND="python ${NGSANE_BASE}/tools/fithic-fixedBins/fithicCountInteractions.py --create2DMatrix $TADBIT --mappability=$MAPPABILITY --resolution=$HIC_RESOLUTION --chromsizes=$GENOME_CHROMSIZES $FITHIC_CHROMOSOMES --outputDir=$OUTDIR/$SAMPLE $SORTEDDATASET --outputFilename $SAMPLE > $OUTDIR/$SAMPLE.log"
    echo $RUN_COMMAND && eval $RUN_COMMAND

    [ -e $OUTDIR/$SAMPLE/${SAMPLE}$ASD.bam.fragmentLists ] && mv $OUTDIR/$SAMPLE/${SAMPLE}$ASD.bam.fragmentLists $OUTDIR/$SAMPLE/$SAMPLE.fragmentLists
    [ -e $OUTDIR/$SAMPLE/${SAMPLE}$ASD.bam.contactCounts ] && mv $OUTDIR/$SAMPLE/${SAMPLE}$ASD.bam.contactCounts $OUTDIR/$SAMPLE/$SAMPLE.contactCounts
    
    $GZIP $OUTDIR/$SAMPLE/$SAMPLE.fragmentLists $OUTDIR/$SAMPLE/$SAMPLE.contactCounts

    # mark checkpoint
    NGSANE_CHECKPOINT_CHECK $OUTDIR/$SAMPLE/$SAMPLE.fragmentLists.gz $OUTDIR/$SAMPLE/$SAMPLE.contactCounts.gz

fi

################################################################################
NGSANE_CHECKPOINT_INIT "HiCorrector"

if [[ $(NGSANE_CHECKPOINT_TASK) == "start" ]]; then

    if [[ "$CPU_FITHIC" -gt 1 ]]; then
        RUN_COMMAND=$(which mpirun)" -np $CPU_FITHIC ic_mep --jobID=$SAMPLE --hasHeaderRow=0 --maxIteration=$HICORRECTOR_MAXITER --numRows="$(wc -l $OUTDIR/$SAMPLE/$SAMPLE.matrix | awk '{print $1}')" --numTask=$CPU_FITHIC --memSizePerTask="$(echo "1 + $MEMORY_FITHIC * 1000 / $CPU_FITHIC" | bc)" --inputFile=$OUTDIR/$SAMPLE/$SAMPLE.matrix --outputFile=$OUTDIR/$SAMPLE/$SAMPLE.ice.txt > $OUTDIR/$SAMPLE/$SAMPLE.matrix_log"
    else
        RUN_COMMAND="ic_mes $OUTDIR/$SAMPLE/$SAMPLE.matrix $MEMORY_FITHIC "$(wc -l $OUTDIR/$SAMPLE/$SAMPLE.matrix | awk '{print $1}')" $HICORRECTOR_MAXITER 0 0 $OUTDIR/$SAMPLE/$SAMPLE.ice.txt > $OUTDIR/$SAMPLE/$SAMPLE.matrix_log"     
    fi
    echo $RUN_COMMAND && eval $RUN_COMMAND

    $GZIP $OUTDIR/$SAMPLE/$SAMPLE*.matrix

    # convert to fit-hi-c expected bias format
    paste <(zcat $OUTDIR/$SAMPLE/$SAMPLE.fragmentLists.gz | cut -f1,2) $OUTDIR/$SAMPLE/$SAMPLE.ice.txt | awk '{$3==0?$3=1:$3=$3; print $0}' | $GZIP > $OUTDIR/$SAMPLE/$SAMPLE.ice.txt.gz  
    rm $OUTDIR/$SAMPLE/$SAMPLE.ice.txt
    
    # mark checkpoint
    NGSANE_CHECKPOINT_CHECK $OUTDIR/$SAMPLE/$SAMPLE.ice.txt.gz

fi

################################################################################
NGSANE_CHECKPOINT_INIT "call topological domains (with TADbit)"

if [[ $(NGSANE_CHECKPOINT_TASK) == "start" ]]; then

    if [ -n "$TADBIT" ]; then

        mkdir -p $OUTDIR/$SAMPLE/$SAMPLE
        RUN_COMMAND="python ${NGSANE_BASE}/tools/fithic-fixedBins/callTADs.py --outputDir=$OUTDIR/$SAMPLE --outputFilename=$SAMPLE --threads=$CPU_FITHIC --resolution=$HIC_RESOLUTION $OUTDIR/$SAMPLE/$SAMPLE.*.matrix.gz >> $OUTDIR/$SAMPLE.log"
        echo $RUN_COMMAND && eval $RUN_COMMAND

        cat /dev/null > $OUTDIR/$SAMPLE.tad.bed
        # convert .border file to beds
        for i in $OUTDIR/$SAMPLE/*.border; do
            CHROM=$(echo $i | sed 's/.*.\(.*\).border/\1/')
            awk -v c=$CHROM -v r=$HIC_RESOLUTION 'BEGIN{OFS="\t"}{if (NR>1){print c,$2*r,$3*r,c"_"$1,int($4),"."}}' $i >> $OUTDIR/$SAMPLE.tad.bed
        done
        rm -r $OUTDIR/$SAMPLE/*.border

        # mark checkpoint
        NGSANE_CHECKPOINT_CHECK

        if [ -z "$FITHIC_KEEPCONTACTMATRIX" ]; then
            rm -f $OUTDIR/$SAMPLE/$SAMPLE*.matrix.gz
        fi
        
    else
        echo "[NOTE] skipping topological domain calling (TADbit not found)"
        NGSANE_CHECKPOINT_CHECK
    fi
fi

################################################################################
NGSANE_CHECKPOINT_INIT "fit-hi-c"

if [[ $(NGSANE_CHECKPOINT_TASK) == "start" ]]; then

    cd $OUTDIR/$RESOLUTION
    RUN_COMMAND="python ${NGSANE_BASE}/tools/fithic-fixedBins/fit-hi-c-fixedSize-withBiases.py $FITHICADDPARAM --lib=${SAMPLE} --biases=$OUTDIR/$SAMPLE/$SAMPLE.ice.txt.gz --fragments=$OUTDIR/$SAMPLE/$SAMPLE.fragmentLists.gz --interactions=$OUTDIR/$SAMPLE/$SAMPLE.contactCounts.gz --resolution $HIC_RESOLUTION >> $OUTDIR/$SAMPLE.log"
    echo $RUN_COMMAND && eval $RUN_COMMAND
    
    zcat $OUTDIR/$SAMPLE.spline_pass1.res$HIC_RESOLUTION.significances.txt.gz | awk -v q=$FITHIC_QVALUETHRESHOLD '$7<=q' | sort -k7g | gzip > $OUTDIR/$SAMPLE.txt.gz

    SIGCISINTERACTIONS=$(zcat $OUTDIR/$SAMPLE.txt.gz |  awk '$1==$3' | wc -l | cut -d' ' -f 2)
    SIGTRANSINTERACTIONS=$(zcat $OUTDIR/$SAMPLE.txt.gz |  awk '$1!=$3' | wc -l | cut -d' ' -f 2)
    echo "Significant cis interactions: $SIGCISINTERACTIONS" >> $OUTDIR/$SAMPLE.log
    echo "Significant trans interactions: $SIGTRANSINTERACTIONS" >> $OUTDIR/$SAMPLE.log
    
    # mark checkpoint
    NGSANE_CHECKPOINT_CHECK $OUTDIR/$SAMPLE.txt.gz
fi

################################################################################
[ -e $OUTDIR/$FITHIC_POOLED_SAMPLE_NAME.txt.gz.dummy ] && rm $OUTDIR/$FITHIC_POOLED_SAMPLE_NAME.txt.gz.dummy
echo ">>>>> Chromatin organization with fit-hi-c - FINISHED"
echo ">>>>> enddate "`date`

