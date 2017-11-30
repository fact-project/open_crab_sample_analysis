# open_crab_sample_analysis

Sample Gamma Analysis on our Open Crab Sample


## Software installation

We recommend anaconda, download here: https://www.anaconda.com/download

* After installing, create a new environment for the FACT analysis:

```
$ conda create -n fact python=3.6 ipython matplotlib scikit-learn==0.19.0 pandas astropy pymongo tqdm h5py pymysql sqlalchemy pytables wrapt click pyyaml joblib
```

* Activate the environment

```
$ source activate fact
```

* Install the non-conda requirements

```
$ pip install -r requirements.txt
```

* run the analysis

```
$ make
```
