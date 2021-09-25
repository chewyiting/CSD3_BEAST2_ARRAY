#!/bin/bash
#!

#!#############################################################
#!#### Modify the options in this section as appropriate ######
#!#############################################################

#SBATCH -J foo 						# Name of the job. 
#SBATCH -A XXXXXX-SL3-CPU	 		# Which project should be charged:
#SBATCH --output=foo_%A_%a.log 		# Output filename: %A means slurm job ID
#SBATCH --error=foo_%A_%a.err 		# Redirect error messages with: -e <file_name>
#SBATCH --mail-type=ALL
#SBATCH --array=1-8 				# %a will take on values 1-8

#! How many (MPI) tasks will there be in total? (<= nodes*32)
#! The skylake/skylake-himem nodes have 32 CPUs (cores) each.
#! By default SLURM will assume 1 task per node and 1 CPU per task.
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8 			# How many many cores will be allocated per task? 
#SBATCH --time=12:00:00

#! For 6GB per CPU, set "-p skylake"; for 12GB per CPU, set "-p skylake-himem": 
#! Do not use the cclake partition
#SBATCH -p skylake

################################################################################
#! sbatch directives end here (put any additional directives above this line)
################################################################################

#! Notes:
#! Charging is determined by core number*walltime.
#! The --ntasks value refers to the number of tasks to be launched by SLURM only. This
#! usually equates to the number of MPI tasks launched. Reduce this from nodes*32 if
#! demanded by memory requirements, or if OMP_NUM_THREADS>1.
#! Each task is allocated 1 core by default, and each core is allocated 5980MB (skylake)
#! and 12030MB (skylake-himem). If this is insufficient, also specify
#! --cpus-per-task and/or --mem (the latter specifies MB per node).

#SBATCH --mem=1536 					# 1024 = 1GB

#! Number of nodes and tasks per node allocated by SLURM (do not change):
numnodes=$SLURM_JOB_NUM_NODES
numtasks=$SLURM_NTASKS
mpi_tasks_per_node=$(echo "$SLURM_TASKS_PER_NODE" | sed -e  's/^\([0-9][0-9]*\).*$/\1/')

#! ##############################################################################
#! Modify the settings below to specify the application's environment, location 
#! and launch method:
#! ##############################################################################

#! Optionally modify the environment seen by the application
#! (note that SLURM reproduces the environment at submission irrespective of ~/.bashrc):
. /etc/profile.d/modules.sh                # Leave this line (enables the module command)
module purge                               # Removes all modules still loaded
module load rhel7/default-peta4            # REQUIRED - loads the basic environment

#! Insert additional module load commands after this line if needed:
module load beagle-lib-2.1.2-gcc-4.8.5-ti5kq5r

#! Full path to application executable: 
#! This should be the path to where you installed BEAST

FILENAME=$(sed -n ${SLURM_ARRAY_TASK_ID}p input.list) 	# input.list stores names of input files, line by line
STATENAME=$(sed -n ${SLURM_ARRAY_TASK_ID}p state.list) 	# state.list stores names of state files, line by line

application="/home/ytc34/rds/hpc-work/Mbovis/BEAST/BEAST2/beast/bin/beast" 

#! Uncomment one of the following

# options="-java -seed $RANDOM -threads ${SLURM_CPUS_PER_TASK} -beagle_SSE ${FILENAME}" # Run BEAST on XML file for the first time
# options="-java -resume -statefile ${STATENAME} -threads ${SLURM_CPUS_PER_TASK} -beagle_SSE ${FILENAME}" # Resume BEAST run from state file

#! Work directory (i.e. where the job will run):
workdir="$SLURM_SUBMIT_DIR"  # The value of SLURM_SUBMIT_DIR sets workdir to the directory
                             # in which sbatch is run.

#! Are you using OpenMP (NB this is unrelated to OpenMPI)? If so increase this
#! safe value to no more than 32:
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK}

#! Number of MPI tasks to be started by the application per node and in total (do not change):
np=$[${numnodes}*${mpi_tasks_per_node}]

#! The following variables define a sensible pinning strategy for Intel MPI tasks -
#! this should be suitable for both pure MPI and hybrid MPI/OpenMP jobs:
export I_MPI_PIN_DOMAIN=omp:compact # Domains are $OMP_NUM_THREADS cores in size
export I_MPI_PIN_ORDER=scatter # Adjacent domains have minimal sharing of caches/sockets
#! Notes:
#! 1. These variables influence Intel MPI only.
#! 2. Domains are non-overlapping sets of cores which map 1-1 to MPI tasks.
#! 3. I_MPI_PIN_PROCESSOR_LIST is ignored if I_MPI_PIN_DOMAIN is set.
#! 4. If MPI tasks perform better when sharing caches/sockets, try I_MPI_PIN_ORDER=compact.


#! Uncomment one choice for CMD below (add mpirun/mpiexec options if necessary):

#! Choose this for a MPI code (possibly using OpenMP) using Intel MPI.
#! CMD="mpirun -ppn $mpi_tasks_per_node -np $np $application $options"

#! Choose this for a pure shared-memory OpenMP parallel program on a single node:
#! (OMP_NUM_THREADS threads will be created):

CMD="$application $options"

#! Choose this for a MPI code (possibly using OpenMP) using OpenMPI:
#! CMD="mpirun -npernode $mpi_tasks_per_node -np $np $application $options"


###############################################################
### You should not have to change anything below this line ####
###############################################################

cd $workdir
echo -e "Changed directory to `pwd`.\n"

JOBID=$SLURM_JOB_ID

echo -e "JobID: $JOBID\n======"
echo "Time: `date`"
echo "Running on master node: `hostname`"
echo "Current directory: `pwd`"

if [ "$SLURM_JOB_NODELIST" ]; then
        #! Create a machine file:
        export NODEFILE=`generate_pbs_nodefile`
        cat $NODEFILE | uniq > machine.file.$JOBID
        echo -e "\nNodes allocated:\n================"
        echo `cat machine.file.$JOBID | sed -e 's/\..*$//g'`
fi

echo "My SLURM_ARRAY_JOB_ID is $SLURM_ARRAY_JOB_ID."
echo "My SLURM_ARRAY_TASK_ID is $SLURM_ARRAY_TASK_ID"
echo "My input file is $FILENAME"
echo "My state file is $STATENAME"

echo -e "\nnumtasks=$numtasks, numnodes=$numnodes, mpi_tasks_per_node=$mpi_tasks_per_node (OMP_NUM_THREADS=$OMP_NUM_THREADS)"

echo -e "\nExecuting command:\n==================\n$CMD\n"

eval $CMD 
