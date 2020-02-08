/*

THIS IS PROVIDED AS IS WITHOUT ANY WARRANTY AND IT IS FOR EDUCATIONAL
PURPOSES ONLY. NEITHER I NOR ANY OF MY EMPLOYERS PAST, PRESENT, NOR FUTURE
CAN BE HELD LIABLE FOR ANY DAMAGES THE USAGE OF THIS CODE MAY CAUSE. IT IS
IMPORTANT TO ALWAYS TEST ANY CODE IN A TESTING ENVIRONMENT PRIOR TO
USAGE IN PRODUCTION.

*/

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;

namespace Microsoft.Support.Samples
{
    /// <summary>
    /// Represents the object pool mode
    /// </summary>
    public enum ObjectPoolLoadMode
    {
        Eager,
        Lazy
    }

    /// <summary>
    /// Represents an object pool of an object type in order to control predicatable resources for this object
    /// </summary>
    /// <typeparam name="T">T can be of any type. However, the intention here is to manage types</typeparam>
    public class ObjectPool<T>
    {
        // TODO: Performance counter reporting and debug tracing
        // TODO: Convert to async

        private readonly Queue<T> _items;
        private readonly int _maxSize;
        private int _currentSize;
        private readonly object[] _constructorParameters;
        private readonly ObjectPoolLoadMode _loadMode;
        private static readonly ReaderWriterLockSlim _expandoLock = new ReaderWriterLockSlim(LockRecursionPolicy.NoRecursion);

        private ObjectPool(ObjectPoolLoadMode loadMode, int maxSize, int currentSize, Queue<T> items, object[] constructorParameters)
        {
            _maxSize = maxSize;
            _currentSize = currentSize;
            _items = items;
            _constructorParameters = constructorParameters;
            _loadMode = loadMode;
        }

        /// <summary>
        /// Constructs an eager loading object pool
        /// </summary>
        /// <param name="maxSize">The maximum size of the poool</param>
        /// <param name="constructorParameters">Constructor parameter for the objects</param>
        /// <returns>An eager-loading object pool of type T</returns>
        public static ObjectPool<T> CreateEager(int maxSize, params object[] constructorParameters)
        {
            return Create(ObjectPoolLoadMode.Eager, 0, maxSize, constructorParameters);
        }

        /// <summary>
        /// Constructs an eager loading object pool
        /// </summary>
        /// <param name="minSize">A starting size for the pool</param>
        /// <param name="maxSize">The maximum size of the pool</param>
        /// <param name="constructorParameters">Constructor parameter for the objects</param>
        /// <returns>An lazy-loading object pool of type T</returns>
        public static ObjectPool<T> CreateLazy(int minSize, int maxSize, params object[] constructorParameters)
        {
            return Create(ObjectPoolLoadMode.Lazy, minSize, maxSize, constructorParameters);
        }

        private static T CreateObject(params object[] constructorParameters)
        {            
            return (T)Activator.CreateInstance(typeof(T), constructorParameters);
        }

        private static ObjectPool<T> Create(ObjectPoolLoadMode mode, int minSize, int maxSize, params object[] constructorParameters)
        {
            if (minSize < 0)
                throw new ArgumentException("minSize cannot be less than zero", nameof(minSize));
            if (maxSize < 0)
                throw new ArgumentException("maxSize cannot be less than zero", nameof(maxSize));

            if (minSize > maxSize)
                throw new ArgumentOutOfRangeException("minSize greater than maxSize zero", nameof(minSize));

            Type gType = typeof(T);
            List<Type> objectTypes = new List<Type>(constructorParameters.Length);
            foreach (object obj in constructorParameters)
                objectTypes.Add(obj.GetType());

            Queue<T> items = new Queue<T>(maxSize);
            int currentSize = mode == ObjectPoolLoadMode.Eager ? maxSize : minSize;

            for (int i = 0; i < currentSize; i++)
                items.Enqueue(CreateObject(constructorParameters));

            return new ObjectPool<T>(mode, maxSize, currentSize, items, constructorParameters);
        }

        /// <summary>
        /// Acquires an object from the pool, but throws an exception if the pool is depleted
        /// </summary>
        /// <returns>Acquired object</returns>
        public T Acquire()
        {
            return Acquire(0);
        }

        /// <summary>
        /// Acquires an object from the pool
        /// </summary>
        /// <param name="millisconds">Time to wait for acquiring an item from the pool</param>
        /// <returns>Object of type t from the pool</returns>
        public T Acquire(int millisconds)
        {
            if (millisconds < 0)
                throw new ArgumentOutOfRangeException("The milliseconds argument cannot be less than 0", nameof(millisconds));

            Stopwatch adquisitionTime = new Stopwatch();
            adquisitionTime.Start();

            _expandoLock.EnterUpgradeableReadLock();
            try
            {
                if (_items.Count == 0)
                {
                    // If the pool is eager, it should already have reached its max size, so we can't grow
                    if (_loadMode == ObjectPoolLoadMode.Eager || _currentSize == _maxSize)
                    {
                        if (millisconds > 0)
                        {
                            while (adquisitionTime.ElapsedMilliseconds < millisconds)
                            {
                                Thread.Sleep(10);
                                if (_items.Count > 0)
                                    return _items.Dequeue();
                            }
                            throw new TimeoutException($"Could not acquire an object in {millisconds}ms. Object pool or {typeof(T).Name} is full. Please try again later.");
                        }

                        throw new InvalidOperationException("Could not acquire an object from this pool. Object pool or {typeof(T).Name} is full. Please try again later.");
                    }
                    else // Pool is depleted, but we can grow
                    {
                        _expandoLock.EnterWriteLock();
                        try
                        {
                            T item = CreateObject(_constructorParameters);
                            _currentSize++;
                            return item;
                        }
                        finally
                        {
                            _expandoLock.ExitWriteLock();
                        }
                    }
                }

                return _items.Dequeue();
            }
            finally
            {
                adquisitionTime.Stop();
                _expandoLock.ExitUpgradeableReadLock();
            }
        }

        /// <summary>
        /// It is important to call release on the object in order to return it to the pool, otherwise it will be exhausted
        /// </summary>
        /// <param name="item">The item to release</param>
        public void Release(T item)
        {
            _expandoLock.EnterWriteLock();
            try
            {
                _items.Enqueue(item);
            }
            finally
            {
                _expandoLock.ExitWriteLock();
            }
        }
    }
}
